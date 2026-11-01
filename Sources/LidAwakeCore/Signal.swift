import Foundation

/// Darwin notifications between processes. They carry no data and work from the sandboxed widget.
public enum Signal: String, CaseIterable, Sendable {
    /// State changed (posted by whoever changed it). The app refreshes its UI and the widget.
    case changed = "dev.habibtalib.lidawake.changed"
    /// The widget wrote a request to the App Group container. The app applies it.
    case request = "dev.habibtalib.lidawake.request"
    /// An agent pinged (hook, keepalive or release). The app re-evaluates the rules right away.
    case activity = "dev.habibtalib.lidawake.activity"

    public static func post(_ signal: Signal) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(signal.rawValue as CFString), nil, nil, true)
    }

    /// Calls `handler` on the main queue each time `signal` is posted. Keep the returned token alive.
    public static func observe(_ signal: Signal, handler: @escaping @Sendable () -> Void) -> Observation {
        Observation(signal: signal, handler: handler)
    }

    public final class Observation: @unchecked Sendable {
        let handler: @Sendable () -> Void
        let name: CFString

        init(signal: Signal, handler: @escaping @Sendable () -> Void) {
            self.handler = handler
            self.name = signal.rawValue as CFString
            let observer = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<Observation>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { me.handler() }
            }, name, nil, .deliverImmediately)
        }

        deinit {
            CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                               Unmanaged.passUnretained(self).toOpaque(),
                                               CFNotificationName(name), nil)
        }
    }
}
