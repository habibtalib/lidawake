import CoreGraphics

public enum UserIdle {
    /// Seconds since the last keyboard, mouse or trackpad event in this login session.
    public static func seconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
