import Foundation
import LidAwakeCore

// Minimal MCP server over stdio: newline-delimited JSON-RPC 2.0, tools only.

func log(_ message: String) {
    FileHandle.standardError.write(Data("lidawake-mcp: \(message)\n".utf8))
}

func send(_ message: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else {
        log("could not encode response")
        return
    }
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
}

func schema(_ properties: [String: [String: Any]], required: [String] = []) -> [String: Any] {
    ["type": "object", "properties": properties, "required": required]
}

let tools: [[String: Any]] = [
    [
        "name": "lidawake_status",
        "description": "Show whether the Mac is kept awake with the lid closed (pmset disablesleep), time left, battery level and whether the permission is installed.",
        "inputSchema": schema([:]),
    ],
    [
        "name": "lidawake_on",
        "description": "Keep the Mac awake with the lid closed, e.g. during a long build or agent run. Optionally for a limited time and with a battery floor. The LidAwake menu bar app enforces the timer and floor.",
        "inputSchema": schema([
            "minutes": ["type": "integer", "description": "Turn sleep back on after this many minutes. Omit to stay on until turned off."],
            "battery_floor": ["type": "integer", "description": "Turn sleep back on when on battery at or below this percentage (1–99)."],
            "agent_mode": ["type": "boolean", "description": "Also switch on agent mode: LidAwake then turns on while Claude Code works and off once it is quiet."],
        ]),
    ],
    [
        "name": "lidawake_keepalive",
        "description": "Hold the Mac awake while you work (long builds, test runs, deploys, agent tasks), even with the lid closed. Turns LidAwake on if needed. Call again before it expires to extend; call lidawake_release when done so the Mac can sleep.",
        "inputSchema": schema([
            "minutes": ["type": "integer", "description": "How long to hold (default 30). Extend by calling again."],
            "reason": ["type": "string", "description": "Short label shown to the user, e.g. 'npm test in repo X'."],
        ]),
    ],
    [
        "name": "lidawake_release",
        "description": "End your keepalive. The Mac then follows the user's rules again (agent mode, idle, network) and may go back to sleep.",
        "inputSchema": schema([
            "reason": ["type": "string", "description": "The same label used for lidawake_keepalive. Omit to release all keepalives."],
        ]),
    ],
    [
        "name": "lidawake_off",
        "description": "Let the Mac sleep normally again when the lid closes.",
        "inputSchema": schema([:]),
    ],
]

struct ToolError: Error {
    let message: String
}

func int(_ value: Any?) -> Int? {
    switch value {
    case let n as NSNumber: return n.intValue
    case let s as String: return Int(s.trimmingCharacters(in: .whitespaces))
    default: return nil
    }
}

func appIsRunning() -> Bool {
    (try? Shell.run("/usr/bin/pgrep", ["-f", "LidAwake.app/Contents/MacOS/"]).status) == 0
}

func callTool(_ name: String, _ args: [String: Any]) throws -> String {
    switch name {
    case "lidawake_status":
        let rules = AutoRules.load()
        let activity = Controller.snapshot()
        let now = Date()
        let leases = activity.store.activeLeases(at: now).map { "\($0.reason) (\(Duration.format($0.until.timeIntervalSince(now))) left)" }
        return Controller.status().summary()
            + "\nRules: \(rules.summary)."
            + "\nAgents: \(activity.agentBusy(at: now, window: rules.busyWindow) ? "working" : "quiet")"
            + (leases.isEmpty ? "" : "; keepalives: " + leases.joined(separator: ", ")) + "."
    case "lidawake_on":
        let minutes = int(args["minutes"])
        let floor = int(args["battery_floor"])
        if let floor, !(1...99).contains(floor) { throw ToolError(message: "'battery_floor' must be 1–99.") }
        if (args["agent_mode"] as? Bool) == true {
            var rules = AutoRules.load()
            rules.agentMode = true
            try rules.save()
        }
        var text = try Controller.turnOn(minutes: minutes, batteryFloor: floor, origin: .mcp).summary()
        if (minutes != nil || floor != nil) && !appIsRunning() {
            text += "\nWarning: the LidAwake app is not running, so the timer and battery floor are not enforced. Call lidawake_off when done."
        }
        return text
    case "lidawake_keepalive":
        let minutes = max(1, min(int(args["minutes"]) ?? 30, 24 * 60))
        let reason = (args["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "agent"
        var text = try Controller.keepalive(minutes: minutes, reason: reason, source: .mcp).summary()
        text += "\nKeepalive '\(reason)' holds for \(minutes) min."
        if !appIsRunning() { text += "\nWarning: the LidAwake app is not running, so nothing will release this automatically. Call lidawake_release when done." }
        return text
    case "lidawake_release":
        let reason = (args["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return try Controller.release(reason: reason).summary() + "\nReleased \(reason.map { "'\($0)'" } ?? "all keepalives")."
    case "lidawake_off":
        return try Controller.turnOff().summary()
    default:
        throw ToolError(message: "Unknown tool '\(name)'.")
    }
}

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty,
          let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
    // Notifications (no id) need no reply.
    guard let id = message["id"] else { continue }
    let method = message["method"] as? String ?? ""
    let params = message["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        send(["jsonrpc": "2.0", "id": id, "result": [
            "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "lidawake", "version": LidAwakeVersion.string],
        ]])
    case "ping":
        send(["jsonrpc": "2.0", "id": id, "result": [String: Any]()])
    case "tools/list":
        send(["jsonrpc": "2.0", "id": id, "result": ["tools": tools]])
    case "tools/call":
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        let result: [String: Any]
        do {
            result = ["content": [["type": "text", "text": try callTool(name, args)]]]
        } catch let error as ToolError {
            result = ["content": [["type": "text", "text": error.message]], "isError": true]
        } catch {
            result = ["content": [["type": "text", "text": "\(error)"]], "isError": true]
        }
        send(["jsonrpc": "2.0", "id": id, "result": result])
    default:
        send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
    }
}
