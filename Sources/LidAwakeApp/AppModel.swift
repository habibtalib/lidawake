import AppKit
import IOKit.ps
import LidAwakeCore
import Network
import ServiceManagement
import SwiftUI
import UserNotifications
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var status = Status(sleepDisabled: false, permissionInstalled: false, session: nil, battery: .desktop)
    @Published private(set) var now = Date()
    @Published var errorMessage: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Battery floor applied to sessions started from the app or widget. 0 = off.
    @AppStorage("batteryFloor") var batteryFloor = 20
    /// Auto on/off rules (shared with the CLI and MCP through rules.json).
    @Published private(set) var rules = AutoRules.load()
    @Published private(set) var activity = ActivitySnapshot()
    @Published private(set) var networkDownSince: Date?
    @Published private(set) var hooksInstalled = ClaudeHooks.isInstalled()

    private let pathMonitor = NWPathMonitor()
    private var lastTick = Date.distantPast

    private var timer: Timer?
    private var observations: [Signal.Observation] = []
    private var powerSource: CFRunLoopSource?
    private var lastSnapshot: WidgetSnapshot?

    static let presets: [(label: String, minutes: Int?)] = [
        ("30m", 30), ("1h", 60), ("2h", 120), ("4h", 240), ("∞", nil),
    ]

    func start() {
        refresh()
        // Re-check every 30 s: enforce the timer and battery floor, update the countdown, keep the widget snapshot fresh.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { AppModel.shared.tick() }
        }
        observations = [
            Signal.observe(.changed) { MainActor.assumeIsolated { AppModel.shared.refresh() } },
            Signal.observe(.request) { MainActor.assumeIsolated { AppModel.shared.applyWidgetRequest() } },
            // Hooks and keepalives: re-evaluate straight away (at most every 2 s).
            Signal.observe(.activity) { MainActor.assumeIsolated { AppModel.shared.tick(minimumGap: 2) } },
        ]
        observeNetwork()
        observePowerSource()
        applyWidgetRequest()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        }
    }

    func tick(minimumGap: TimeInterval = 0) {
        guard Date().timeIntervalSince(lastTick) >= minimumGap else { return }
        lastTick = Date()
        rules = AutoRules.load()
        switch Controller.enforce(rules: rules, networkDownSince: networkDownSince,
                                  agentBatteryFloor: batteryFloor > 0 ? batteryFloor : nil) {
        case .turnOff(let reason): notify("Sleep is back on", reason.description)
        case .turnOn(let reason): notify("Keeping the Mac awake", reason.description)
        default: break
        }
        refresh()
    }

    func refresh() {
        now = Date()
        status = Controller.status()
        activity = Controller.snapshot(networkDownSince: networkDownSince)
        hooksInstalled = ClaudeHooks.isInstalled()
        publishWidgetSnapshot()
    }

    // MARK: Agent mode and auto rules

    var agentBusy: Bool { activity.agentBusy(at: now, window: rules.busyWindow) }

    /// "2 sessions working", "Working (transcript)", "Quiet for 12m" or "No agent activity yet".
    var agentStatusLine: String {
        let working = activity.workingSessions(at: now, window: rules.busyWindow)
        let leases = activity.store.activeLeases(at: now)
        if let lease = leases.first { return "Held by \(lease.reason) · \(Duration.format(lease.until.timeIntervalSince(now))) left" }
        if working > 0 { return working == 1 ? "1 session working" : "\(working) sessions working" }
        if agentBusy { return "Working" }
        if let last = activity.lastAgentActivity(at: now) { return "Quiet for \(Duration.format(now.timeIntervalSince(last)))" }
        return "No agent activity yet"
    }

    func updateRules(_ change: (inout AutoRules) -> Void) {
        var next = rules
        change(&next)
        do {
            try next.save()
            rules = next
        } catch {
            errorMessage = "Could not save rules: \(error.localizedDescription)"
        }
        tick()
    }

    func installHooks() {
        do {
            try ClaudeHooks.install(command: ClaudeHooks.defaultCommand())
            errorMessage = nil
        } catch {
            errorMessage = "Hooks: \(error)"
        }
        refresh()
    }

    private func observeNetwork() {
        pathMonitor.pathUpdateHandler = { path in
            let up = path.status == .satisfied
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let model = AppModel.shared
                    if up { model.networkDownSince = nil } else if model.networkDownSince == nil { model.networkDownSince = Date() }
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "dev.habibtalib.lidawake.network"))
    }

    var remaining: TimeInterval? { status.remaining(now: now) }

    // MARK: Actions

    func turnOn(minutes: Int?, origin: Origin = .app) {
        perform { try Controller.turnOn(minutes: minutes, batteryFloor: self.batteryFloor > 0 ? self.batteryFloor : nil, origin: origin) }
    }

    /// Adds time to the running timer (or starts one from now when there is none).
    func extend(minutes: Int) {
        let left = remaining.map { max(0, Int(($0 / 60).rounded(.up))) } ?? 0
        turnOn(minutes: left + minutes, origin: status.session?.origin ?? .app)
    }

    /// 0…1 share of the timer still left, nil without a timer.
    var timerProgress: Double? {
        guard let session = status.session, let deadline = session.deadline else { return nil }
        let total = deadline.timeIntervalSince(session.startedAt)
        guard total > 0 else { return nil }
        return min(1, max(0, deadline.timeIntervalSince(now) / total))
    }

    func turnOff() {
        perform { try Controller.turnOff() }
    }

    func toggle(origin: Origin = .app) {
        status.sleepDisabled ? turnOff() : turnOn(minutes: nil, origin: origin)
    }

    func installPermission() {
        do {
            try SudoersRule.install()
            errorMessage = nil
        } catch SudoersRule.Failure.cancelled {
        } catch {
            errorMessage = "\(error)"
        }
        refresh()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func perform(_ action: () throws -> Status) {
        do {
            status = try action()
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
            status = Controller.status()
        }
        now = Date()
        publishWidgetSnapshot()
    }

    // MARK: Widget

    /// Applies a tap the widget handed over through the App Group container.
    func applyWidgetRequest() {
        guard let url = WidgetBridge.requestURL,
              let request = WidgetBridge.read(WidgetRequest.self, from: url) else { return }
        try? FileManager.default.removeItem(at: url)
        guard request.isFresh() else { return }
        switch request.action {
        case .on: turnOn(minutes: request.minutes, origin: .widget)
        case .off: turnOff()
        case .toggle: status.sleepDisabled ? turnOff() : turnOn(minutes: request.minutes, origin: .widget)
        }
    }

    private func publishWidgetSnapshot() {
        guard let url = WidgetBridge.snapshotURL else { return }
        let snapshot = WidgetSnapshot(status, now: now)
        try? WidgetBridge.write(snapshot, to: url)
        // Only reload timelines when something the widget shows changed (the timestamp alone does not count).
        var previous = lastSnapshot
        previous?.updatedAt = snapshot.updatedAt
        if previous != snapshot { WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.kind) }
        lastSnapshot = snapshot
    }

    // MARK: Power source changes (plugging in / unplugging, battery level)

    private func observePowerSource() {
        let source = IOPSNotificationCreateRunLoopSource({ _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { AppModel.shared.tick() } }
        }, nil)?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
    }

    private func notify(_ title: String, _ body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
