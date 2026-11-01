import Foundation

/// What the widget shows. The app writes it to the App Group container; the widget only reads it.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var sleepDisabled: Bool
    public var permissionInstalled: Bool
    public var deadline: Date?
    public var batteryFloor: Int?
    public var battery: BatteryStatus

    public init(updatedAt: Date = Date(), sleepDisabled: Bool, permissionInstalled: Bool,
                deadline: Date?, batteryFloor: Int?, battery: BatteryStatus) {
        self.updatedAt = updatedAt
        self.sleepDisabled = sleepDisabled
        self.permissionInstalled = permissionInstalled
        self.deadline = deadline
        self.batteryFloor = batteryFloor
        self.battery = battery
    }

    public init(_ status: Status, now: Date = Date()) {
        self.init(updatedAt: now, sleepDisabled: status.sleepDisabled, permissionInstalled: status.permissionInstalled,
                  deadline: status.session?.deadline, batteryFloor: status.session?.batteryFloor, battery: status.battery)
    }

    /// The app rewrites the snapshot at least every minute while it runs.
    public func appLooksAlive(now: Date = Date()) -> Bool {
        now.timeIntervalSince(updatedAt) < 180
    }

    public static let placeholder = WidgetSnapshot(sleepDisabled: true, permissionInstalled: true,
                                                   deadline: Date().addingTimeInterval(5400), batteryFloor: 20,
                                                   battery: BatteryStatus(percent: 82, onAC: true))
}

/// A widget tap, handed to the app to carry out (the sandboxed widget cannot run sudo).
public struct WidgetRequest: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case on, off, toggle
    }

    public var action: Action
    public var minutes: Int?
    public var createdAt: Date

    public init(action: Action, minutes: Int? = nil, createdAt: Date = Date()) {
        self.action = action
        self.minutes = minutes
        self.createdAt = createdAt
    }

    /// Requests older than this are ignored (for example a tap made while the app was not running long ago).
    public func isFresh(now: Date = Date()) -> Bool {
        now.timeIntervalSince(createdAt) < 600
    }
}

/// Locates the App Group container. The group ID comes from the `LidAwakeAppGroup` Info.plist key,
/// set only in the Xcode build; the SwiftPM-built app has no group, so widget publishing is skipped there.
public enum WidgetBridge {
    public static let urlScheme = "lidawake"
    public static let kind = "LidAwakeWidget"

    public static var appGroupId: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "LidAwakeAppGroup") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }

    static func file(_ name: String) -> URL? {
        guard let group = appGroupId,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return container.appendingPathComponent(name)
    }

    public static var snapshotURL: URL? { file("widget-snapshot.json") }
    public static var requestURL: URL? { file("widget-request.json") }

    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONCoding.encoder.encode(value).write(to: url, options: .atomic)
    }

    public static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONCoding.decoder.decode(type, from: data)
    }

    /// Opens the app and asks it to apply the pending request (used when the app is not running).
    public static let applyURL = URL(string: "\(urlScheme)://apply")!
    public static let panelURL = URL(string: "\(urlScheme)://panel")!
}
