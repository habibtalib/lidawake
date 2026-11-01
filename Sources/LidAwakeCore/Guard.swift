import Foundation

/// Decides when a running session must end. Pure, so it is fully testable.
public enum Guard {
    public enum Decision: Equatable, Sendable {
        case keep
        case turnOff(Reason)
    }

    public enum Reason: Equatable, Sendable, CustomStringConvertible {
        case timerEnded
        case batteryLow(Int)

        public var description: String {
            switch self {
            case .timerEnded: return "The timer ended."
            case .batteryLow(let percent): return "Battery is at \(percent)%."
            }
        }
    }

    public static func evaluate(_ session: Session, battery: BatteryStatus, now: Date = Date()) -> Decision {
        if let deadline = session.deadline, now >= deadline { return .turnOff(.timerEnded) }
        if let floor = session.batteryFloor, !battery.onAC, let percent = battery.percent, percent <= floor {
            return .turnOff(.batteryLow(percent))
        }
        return .keep
    }
}
