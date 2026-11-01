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

    /// Applies the guard once. Returns the reason when it switched sleep back on.
    @discardableResult
    public static func enforce(now: Date = Date()) -> Guard.Reason? {
        guard let session = SessionStore.load(), PowerState.isSleepDisabled() else { return nil }
        guard case .turnOff(let reason) = Guard.evaluate(session, battery: Battery.current(), now: now) else { return nil }
        guard (try? turnOff()) != nil else { return nil }
        return reason
    }
}
