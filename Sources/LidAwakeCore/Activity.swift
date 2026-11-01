import Foundation

/// What agents are doing, shared by the hooks (`lidawake activity`), the MCP keepalive and the app.
/// Stored in `~/Library/Application Support/LidAwake/activity.json`.
public struct ActivityStore: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case hook, mcp, cli
    }

    public struct AgentSession: Codable, Equatable, Sendable {
        public var source: Source
        public var lastSeen: Date
        /// Set by the Stop / SessionEnd hook: the session finished its turn.
        public var done: Bool

        public init(source: Source, lastSeen: Date, done: Bool = false) {
            self.source = source
            self.lastSeen = lastSeen
            self.done = done
        }
    }

    public struct Lease: Codable, Equatable, Sendable {
        public var reason: String
        public var until: Date
        public var source: Source

        public init(reason: String, until: Date, source: Source) {
            self.reason = reason
            self.until = until
            self.source = source
        }
    }

    public var sessions: [String: AgentSession] = [:]
    public var leases: [String: Lease] = [:]

    public init(sessions: [String: AgentSession] = [:], leases: [String: Lease] = [:]) {
        self.sessions = sessions
        self.leases = leases
    }

    /// Records a hook ping. `done` marks the end of the session's turn.
    public mutating func ping(session id: String, source: Source = .hook, done: Bool = false, at now: Date = Date()) {
        sessions[id] = AgentSession(source: source, lastSeen: now, done: done)
    }

    public mutating func hold(reason: String, minutes: Int, source: Source, at now: Date = Date()) {
        leases[Self.leaseKey(reason)] = Lease(reason: reason, until: now.addingTimeInterval(TimeInterval(max(1, minutes)) * 60), source: source)
    }

    public mutating func release(reason: String?) {
        if let reason { leases[Self.leaseKey(reason)] = nil } else { leases.removeAll() }
    }

    public func activeLeases(at now: Date = Date()) -> [Lease] {
        leases.values.filter { $0.until > now }.sorted { $0.until < $1.until }
    }

    /// Drops expired leases and sessions not seen for a day.
    public mutating func prune(at now: Date = Date()) {
        leases = leases.filter { $0.value.until > now }
        sessions = sessions.filter { now.timeIntervalSince($0.value.lastSeen) < 86400 }
    }

    static func leaseKey(_ reason: String) -> String {
        let key = reason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key.isEmpty ? "default" : key
    }

    // MARK: Storage

    public static var url: URL { SessionStore.directory.appendingPathComponent("activity.json") }

    public static func load(from url: URL = url) -> ActivityStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONCoding.decoder.decode(ActivityStore.self, from: data) else { return ActivityStore() }
        return store
    }

    public func save(to url: URL = url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONCoding.encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Load, change, prune and save in one step.
    public static func update(at url: URL = url, now: Date = Date(), _ change: (inout ActivityStore) -> Void) throws {
        var store = load(from: url)
        change(&store)
        store.prune(at: now)
        try store.save(to: url)
    }
}

/// Finds the newest Claude Code transcript write. Only modification times are read, never contents.
public enum TranscriptScanner {
    /// `~/.claude/projects`, `$CLAUDE_CONFIG_DIR/projects` and `~/.claude-profiles/*/projects`, real paths de-duplicated.
    public static func roots(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                             environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        var roots = [home.appendingPathComponent(".claude/projects")]
        if let config = environment["CLAUDE_CONFIG_DIR"], !config.isEmpty {
            roots.append(URL(fileURLWithPath: (config as NSString).expandingTildeInPath).appendingPathComponent("projects"))
        }
        let profiles = home.appendingPathComponent(".claude-profiles")
        if let names = try? FileManager.default.contentsOfDirectory(atPath: profiles.path) {
            roots += names.sorted().map { profiles.appendingPathComponent($0).appendingPathComponent("projects") }
        }
        var seen = Set<String>()
        return roots.filter { url in
            let real = url.resolvingSymlinksInPath().path
            return FileManager.default.fileExists(atPath: real) && seen.insert(real).inserted
        }
    }

    /// Latest modification time of any `*.jsonl` transcript under the roots (one directory level of projects).
    public static func lastWrite(roots: [URL] = roots()) -> Date? {
        let fm = FileManager.default
        var newest: Date?
        for root in roots {
            guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for project in projects {
                // A project folder's mtime changes when a transcript is created, not when one is appended to,
                // so each transcript is checked.
                guard let files = try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
                for file in files where file.pathExtension == "jsonl" {
                    if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                       newest.map({ date > $0 }) ?? true {
                        newest = date
                    }
                }
            }
        }
        return newest
    }
}

/// Everything the guard needs to know about activity, gathered by the app (or `lidawake on --wait`).
public struct ActivitySnapshot: Equatable, Sendable {
    public var lastTranscriptWrite: Date?
    public var store: ActivityStore
    /// Seconds since the last keyboard or mouse event.
    public var userIdleSeconds: TimeInterval
    /// When the network went away; nil while it is available.
    public var networkDownSince: Date?

    public init(lastTranscriptWrite: Date? = nil, store: ActivityStore = ActivityStore(),
                userIdleSeconds: TimeInterval = 0, networkDownSince: Date? = nil) {
        self.lastTranscriptWrite = lastTranscriptWrite
        self.store = store
        self.userIdleSeconds = userIdleSeconds
        self.networkDownSince = networkDownSince
    }

    /// Latest sign of agent work: a transcript write, a hook ping, or a live lease (counts as "now").
    public func lastAgentActivity(at now: Date) -> Date? {
        var dates = [lastTranscriptWrite].compactMap { $0 }
        dates += store.sessions.values.map(\.lastSeen)
        if !store.activeLeases(at: now).isEmpty { dates.append(now) }
        return dates.max()
    }

    /// Hook sessions that are mid-turn (pinged recently and not marked done).
    public func workingSessions(at now: Date, window: TimeInterval) -> Int {
        store.sessions.values.filter { !$0.done && now.timeIntervalSince($0.lastSeen) < window }.count
    }

    /// An agent is working: a live lease, a hook session mid-turn, or a transcript written within `window`.
    /// A transcript write that only belongs to a session whose hook said "done" still counts until the
    /// window passes, which covers the final reply being written.
    public func agentBusy(at now: Date, window: TimeInterval) -> Bool {
        if !store.activeLeases(at: now).isEmpty { return true }
        if workingSessions(at: now, window: window) > 0 { return true }
        if let write = lastTranscriptWrite, now.timeIntervalSince(write) < window { return true }
        return false
    }
}
