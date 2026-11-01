import Foundation

/// Who switched LidAwake on. Shown in the app and in `lidawake status`.
public enum Origin: String, Codable, Sendable, CaseIterable {
    case app, cli, widget, mcp, agent
}

/// The current keep-awake session. Written by whoever turns LidAwake on;
/// the menu bar app enforces the deadline and the battery floor.
public struct Session: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var deadline: Date?
    /// Turn sleep back on when running on battery at or below this percentage.
    public var batteryFloor: Int?
    public var origin: Origin

    public init(startedAt: Date = Date(), deadline: Date? = nil, batteryFloor: Int? = nil, origin: Origin) {
        self.startedAt = startedAt
        self.deadline = deadline
        self.batteryFloor = batteryFloor
        self.origin = origin
    }

    public init(minutes: Int?, batteryFloor: Int?, origin: Origin, now: Date = Date()) {
        self.init(startedAt: now,
                  deadline: minutes.flatMap { $0 > 0 ? now.addingTimeInterval(TimeInterval($0) * 60) : nil },
                  batteryFloor: batteryFloor.flatMap { (1...99).contains($0) ? $0 : nil },
                  origin: origin)
    }
}

/// Session file storage, shared by the app, CLI and MCP server.
/// Lives in `~/Library/Application Support/LidAwake/session.json` (the sandboxed widget never reads it).
public enum SessionStore {
    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LidAwake", isDirectory: true)
    }

    public static var url: URL { directory.appendingPathComponent("session.json") }

    public static func load(from url: URL = url) -> Session? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONCoding.decoder.decode(Session.self, from: data)
    }

    public static func save(_ session: Session?, to url: URL = url) throws {
        if let session {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONCoding.encoder.encode(session).write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

enum JSONCoding {
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
