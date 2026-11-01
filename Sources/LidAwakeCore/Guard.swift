import Foundation

/// Decides what LidAwake should do now. Pure, so it is fully testable.
public enum Guard {
    public enum Decision: Equatable, Sendable {
        case keep
        case turnOff(Reason)
        case turnOn(Reason)
    }

    public enum Reason: Equatable, Sendable, CustomStringConvertible {
        case timerEnded
        case batteryLow(Int)
        case agentsQuiet(Int)
        case idle(Int)
        case networkDown(Int)
        case agentBusy

        public var description: String {
            switch self {
            case .timerEnded: return "The timer ended."
            case .batteryLow(let percent): return "Battery is at \(percent)%."
            case .agentsQuiet(let minutes): return "Claude Code has been quiet for \(minutes) min."
            case .idle(let minutes): return "The Mac has been idle for \(minutes) min."
            case .networkDown(let minutes): return "The network has been down for \(minutes) min."
            case .agentBusy: return "Claude Code is working."
            }
        }
    }

    /// Timer and battery floor only (kept for callers without activity data).
    public static func evaluate(_ session: Session, battery: BatteryStatus, now: Date = Date()) -> Decision {
        if let deadline = session.deadline, now >= deadline { return .turnOff(.timerEnded) }
        if let floor = session.batteryFloor, !battery.onAC, let percent = battery.percent, percent <= floor {
            return .turnOff(.batteryLow(percent))
        }
        return .keep
    }

    /// Full decision. `session` is nil while sleep is allowed (LidAwake off).
    /// - `batteryFloor`: the floor agent mode would use when it turns on by itself.
    public static func evaluate(session: Session?, battery: BatteryStatus, activity: ActivitySnapshot,
                                rules: AutoRules, batteryFloor: Int? = nil, now: Date = Date()) -> Decision {
        let busy = activity.agentBusy(at: now, window: rules.busyWindow)
        let quiet = activity.lastAgentActivity(at: now).map { now.timeIntervalSince($0) } ?? .infinity

        guard let session else {
            // Off: agent mode may turn it on, unless the battery is already at the floor.
            guard rules.agentMode, busy else { return .keep }
            if let floor = batteryFloor, !battery.onAC, let percent = battery.percent, percent <= floor { return .keep }
            if let since = activity.networkDownSince, rules.offWhenNetworkDownMinutes > 0,
               now.timeIntervalSince(since) >= Double(rules.offWhenNetworkDownMinutes) * 60 { return .keep }
            return .turnOn(.agentBusy)
        }

        // The user's own limits come first.
        if case .turnOff(let reason) = evaluate(session, battery: battery, now: now) { return .turnOff(reason) }

        // A live keepalive lease holds the Mac awake regardless of the rules below.
        if !activity.store.activeLeases(at: now).isEmpty { return .keep }

        if let since = activity.networkDownSince, rules.offWhenNetworkDownMinutes > 0 {
            let down = now.timeIntervalSince(since)
            if down >= Double(rules.offWhenNetworkDownMinutes) * 60 { return .turnOff(.networkDown(Int(down / 60))) }
        }

        // Sessions started by agent mode end once agents are quiet; manual ones only when that rule is on.
        let quietLimit = session.origin == .agent ? rules.agentQuietMinutes : rules.offWhenAgentsQuietMinutes
        let sinceStart = now.timeIntervalSince(session.startedAt)
        if quietLimit > 0, !busy {
            // Measure quiet time from the later of the session start and the last activity,
            // so turning LidAwake on by hand is not cut off straight away.
            let quietFor = min(quiet, sinceStart)
            if quietFor >= Double(quietLimit) * 60 { return .turnOff(.agentsQuiet(Int(quietFor / 60))) }
        }

        if rules.offWhenIdleMinutes > 0, !busy {
            let idleFor = min(activity.userIdleSeconds, quiet, sinceStart)
            if idleFor >= Double(rules.offWhenIdleMinutes) * 60 { return .turnOff(.idle(Int(idleFor / 60))) }
        }

        return .keep
    }
}
