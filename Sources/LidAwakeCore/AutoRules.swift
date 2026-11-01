import Foundation

/// Automatic on/off rules, shared by the app, the CLI and the MCP server.
/// Stored in `~/Library/Application Support/LidAwake/rules.json`. Minutes of 0 mean "off".
public struct AutoRules: Codable, Equatable, Sendable {
    /// Turn on by itself while an agent is working, and off once agents have been quiet for `agentQuietMinutes`.
    public var agentMode: Bool
    /// Agent-mode sessions turn off after this long without agent activity.
    public var agentQuietMinutes: Int
    /// Any session (manual too) turns off after this long without agent activity. 0 = off.
    public var offWhenAgentsQuietMinutes: Int
    /// Turn off after this long with no keyboard or mouse input and no agent activity. 0 = off.
    public var offWhenIdleMinutes: Int
    /// Turn off after the network has been unavailable this long. 0 = off.
    public var offWhenNetworkDownMinutes: Int
    /// Activity newer than this counts as "an agent is working".
    public var busyWindowMinutes: Int

    public init(agentMode: Bool = false, agentQuietMinutes: Int = 10, offWhenAgentsQuietMinutes: Int = 15,
                offWhenIdleMinutes: Int = 30, offWhenNetworkDownMinutes: Int = 10, busyWindowMinutes: Int = 3) {
        self.agentMode = agentMode
        self.agentQuietMinutes = agentQuietMinutes
        self.offWhenAgentsQuietMinutes = offWhenAgentsQuietMinutes
        self.offWhenIdleMinutes = offWhenIdleMinutes
        self.offWhenNetworkDownMinutes = offWhenNetworkDownMinutes
        self.busyWindowMinutes = busyWindowMinutes
    }

    public static let `default` = AutoRules()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AutoRules.default
        agentMode = try c.decodeIfPresent(Bool.self, forKey: .agentMode) ?? d.agentMode
        agentQuietMinutes = try c.decodeIfPresent(Int.self, forKey: .agentQuietMinutes) ?? d.agentQuietMinutes
        offWhenAgentsQuietMinutes = try c.decodeIfPresent(Int.self, forKey: .offWhenAgentsQuietMinutes) ?? d.offWhenAgentsQuietMinutes
        offWhenIdleMinutes = try c.decodeIfPresent(Int.self, forKey: .offWhenIdleMinutes) ?? d.offWhenIdleMinutes
        offWhenNetworkDownMinutes = try c.decodeIfPresent(Int.self, forKey: .offWhenNetworkDownMinutes) ?? d.offWhenNetworkDownMinutes
        busyWindowMinutes = try c.decodeIfPresent(Int.self, forKey: .busyWindowMinutes) ?? d.busyWindowMinutes
    }

    public var busyWindow: TimeInterval { TimeInterval(max(1, busyWindowMinutes)) * 60 }

    public static var url: URL { SessionStore.directory.appendingPathComponent("rules.json") }

    public static func load(from url: URL = url) -> AutoRules {
        guard let data = try? Data(contentsOf: url), let rules = try? JSONCoding.decoder.decode(AutoRules.self, from: data) else {
            return .default
        }
        return rules
    }

    public func save(to url: URL = url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONCoding.encoder.encode(self).write(to: url, options: .atomic)
    }

    public var summary: String {
        func m(_ v: Int) -> String { v > 0 ? "\(v)m" : "off" }
        return "agent mode \(agentMode ? "on (off after \(agentQuietMinutes)m quiet)" : "off") · "
            + "agents quiet \(m(offWhenAgentsQuietMinutes)) · idle \(m(offWhenIdleMinutes)) · no network \(m(offWhenNetworkDownMinutes))"
    }
}
