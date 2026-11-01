import Foundation

/// Snapshot of LidAwake's state, as shown by the app, CLI, MCP server and widget.
public struct Status: Codable, Equatable, Sendable {
    public var sleepDisabled: Bool
    public var permissionInstalled: Bool
    public var session: Session?
    public var battery: BatteryStatus

    public init(sleepDisabled: Bool, permissionInstalled: Bool, session: Session?, battery: BatteryStatus) {
        self.sleepDisabled = sleepDisabled
        self.permissionInstalled = permissionInstalled
        self.session = session
        self.battery = battery
    }

    public func remaining(now: Date = Date()) -> TimeInterval? {
        session?.deadline.map { $0.timeIntervalSince(now) }
    }

    /// One readable paragraph.
    public func summary(now: Date = Date()) -> String {
        var lines: [String] = []
        if sleepDisabled {
            var line = "ON: the Mac stays awake with the lid closed"
            if let left = remaining(now: now) { line += " (\(Duration.format(left)) left)" }
            lines.append(line + ".")
            if let floor = session?.batteryFloor { lines.append("Turns off on battery at \(floor)% or lower.") }
            if let origin = session?.origin { lines.append("Started from: \(origin.rawValue).") }
        } else {
            lines.append("OFF: the Mac sleeps normally when the lid closes.")
        }
        if let percent = battery.percent {
            lines.append("Battery: \(percent)%\(battery.onAC ? " (charging / on AC)" : " (on battery)").")
        }
        if !permissionInstalled { lines.append("Permission not installed: run `lidawake install-permission`.") }
        return lines.joined(separator: "\n")
    }
}

/// The one place that changes state. Every front end (app, CLI, MCP, widget via the app) calls this.
public enum Controller {
    public static func status() -> Status {
        let disabled = PowerState.isSleepDisabled()
        return Status(sleepDisabled: disabled,
                      permissionInstalled: SudoersRule.isInstalled(),
                      session: disabled ? SessionStore.load() : nil,
                      battery: Battery.current())
    }

    public static func turnOn(minutes: Int? = nil, batteryFloor: Int? = nil, origin: Origin) throws -> Status {
        try PowerState.setSleepDisabled(true)
        try SessionStore.save(Session(minutes: minutes, batteryFloor: batteryFloor, origin: origin))
        Signal.post(.changed)
        return status()
    }

    public static func turnOff() throws -> Status {
        try PowerState.setSleepDisabled(false)
        try SessionStore.save(nil)
        Signal.post(.changed)
        return status()
    }

    /// Gathers the activity the rules look at. `networkDownSince` comes from the caller's path monitor.
    public static func snapshot(networkDownSince: Date? = nil) -> ActivitySnapshot {
        ActivitySnapshot(lastTranscriptWrite: TranscriptScanner.lastWrite(),
                         store: ActivityStore.load(),
                         userIdleSeconds: UserIdle.seconds(),
                         networkDownSince: networkDownSince)
    }

    /// Applies the timer, battery floor and auto rules once, switching sleep on or off as needed.
    /// Returns the decision it acted on, or nil when nothing changed.
    @discardableResult
    public static func enforce(rules: AutoRules = AutoRules.load(), networkDownSince: Date? = nil,
                               agentBatteryFloor: Int? = nil, now: Date = Date()) -> Guard.Decision? {
        let disabled = PowerState.isSleepDisabled()
        // Sleep can be disabled outside LidAwake (plain pmset); treat that as a manual session from now.
        var session = disabled ? SessionStore.load() : nil
        if disabled && session == nil {
            session = Session(startedAt: now, origin: .cli)
            try? SessionStore.save(session)
        }
        let decision = Guard.evaluate(session: session, battery: Battery.current(), activity: snapshot(networkDownSince: networkDownSince),
                                      rules: rules, batteryFloor: agentBatteryFloor, now: now)
        switch decision {
        case .keep:
            return nil
        case .turnOff:
            return (try? turnOff()) != nil ? decision : nil
        case .turnOn:
            return (try? turnOn(batteryFloor: agentBatteryFloor, origin: .agent)) != nil ? decision : nil
        }
    }

    // MARK: Agent keepalive

    /// Holds the Mac awake for `minutes` on behalf of an agent, turning sleep off if needed.
    public static func keepalive(minutes: Int, reason: String, source: ActivityStore.Source) throws -> Status {
        try ActivityStore.update { $0.hold(reason: reason, minutes: minutes, source: source) }
        Signal.post(.activity)
        if !PowerState.isSleepDisabled() { return try turnOn(origin: source == .mcp ? .mcp : .cli) }
        return status()
    }

    /// Ends a keepalive (or all of them when `reason` is nil). The rules decide from here on.
    public static func release(reason: String?) throws -> Status {
        try ActivityStore.update { $0.release(reason: reason) }
        Signal.post(.activity)
        return status()
    }

    /// A Claude Code hook ping.
    public static func recordHook(session id: String, done: Bool) throws {
        try ActivityStore.update { $0.ping(session: id, source: .hook, done: done) }
        Signal.post(.activity)
    }
}
