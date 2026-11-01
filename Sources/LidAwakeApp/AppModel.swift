import AppKit
import IOKit.ps
import LidAwakeCore
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
        ]
        observePowerSource()
        applyWidgetRequest()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        }
    }

    func tick() {
        if let reason = Controller.enforce() { notify("Sleep is back on", reason.description) }
        refresh()
    }

    func refresh() {
        now = Date()
        status = Controller.status()
        publishWidgetSnapshot()
    }

    var remaining: TimeInterval? { status.remaining(now: now) }

    // MARK: Actions

    func turnOn(minutes: Int?, origin: Origin = .app) {
        perform { try Controller.turnOn(minutes: minutes, batteryFloor: self.batteryFloor > 0 ? self.batteryFloor : nil, origin: origin) }
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
