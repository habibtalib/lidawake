import Foundation

/// Adds or removes LidAwake's Claude Code hooks in `settings.json`:
/// `UserPromptSubmit` and `PreToolUse` run `lidawake activity`; `Stop` and `SessionEnd` run `lidawake activity --done`.
/// Other hooks are never touched. LidAwake's entries are recognised by their command.
public enum ClaudeHooks {
    static let marker = " activity"
    static let busyEvents = ["UserPromptSubmit", "PreToolUse"]
    static let doneEvents = ["Stop", "SessionEnd"]

    public enum Failure: Error, CustomStringConvertible {
        case unreadable(String)

        public var description: String {
            switch self {
            case .unreadable(let path): return "\(path) is not valid JSON; not changed."
            }
        }
    }

    /// `~/.local/bin/lidawake` when installed there, otherwise `lidawake` from PATH.
    public static func defaultCommand(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let local = home.appendingPathComponent(".local/bin/lidawake").path
        return FileManager.default.isExecutableFile(atPath: local) ? local : "lidawake"
    }

    /// Every Claude Code settings file in use: `~/.claude`, `$CLAUDE_CONFIG_DIR` and `~/.claude-profiles/*`
    /// (only where the config folder exists), real paths de-duplicated.
    public static func settingsFiles(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                     environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        var dirs = [home.appendingPathComponent(".claude")]
        if let config = environment["CLAUDE_CONFIG_DIR"], !config.isEmpty {
            dirs.append(URL(fileURLWithPath: (config as NSString).expandingTildeInPath))
        }
        let profiles = home.appendingPathComponent(".claude-profiles")
        if let names = try? FileManager.default.contentsOfDirectory(atPath: profiles.path) {
            dirs += names.sorted().map { profiles.appendingPathComponent($0) }
                .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("projects").path)
                    || FileManager.default.fileExists(atPath: $0.appendingPathComponent("settings.json").path) }
        }
        var seen = Set<String>()
        return dirs.compactMap { dir -> URL? in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let file = dir.appendingPathComponent("settings.json")
            return seen.insert(file.resolvingSymlinksInPath().path).inserted ? file : nil
        }
    }

    public static func isInstalled(files: [URL] = settingsFiles()) -> Bool {
        !files.isEmpty && files.allSatisfy { file in
            guard let root = try? read(file) else { return false }
            return (busyEvents + doneEvents).allSatisfy { event in
                entries(root, event).contains(where: isOurs)
            }
        }
    }

    /// Installs into every settings file. Idempotent; writes `settings.json.lidawake-backup` before the first change.
    public static func install(command: String, files: [URL] = settingsFiles()) throws {
        for file in files {
            var root = try read(file)
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for event in busyEvents + doneEvents {
                var list = (hooks[event] as? [[String: Any]] ?? []).filter { !isOurs($0) }
                var entry: [String: Any] = ["hooks": [[
                    "type": "command",
                    "command": quote(command) + marker + (doneEvents.contains(event) ? " --done" : ""),
                    "timeout": 5,
                ]]]
                if event == "PreToolUse" { entry["matcher"] = "*" }
                list.append(entry)
                hooks[event] = list
            }
            root["hooks"] = hooks
            try write(root, to: file)
        }
    }

    public static func uninstall(files: [URL] = settingsFiles()) throws {
        for file in files where FileManager.default.fileExists(atPath: file.path) {
            var root = try read(file)
            guard var hooks = root["hooks"] as? [String: Any] else { continue }
            for event in busyEvents + doneEvents {
                let list = (hooks[event] as? [[String: Any]] ?? []).filter { !isOurs($0) }
                hooks[event] = list.isEmpty ? nil : list
            }
            root["hooks"] = hooks.isEmpty ? nil : hooks
            try write(root, to: file)
        }
    }

    // MARK: Helpers

    static func entries(_ root: [String: Any], _ event: String) -> [[String: Any]] {
        (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
    }

    /// An entry is ours when all of its commands are `<…>lidawake[" ]activity…`.
    static func isOurs(_ entry: [String: Any]) -> Bool {
        let commands = (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        return !commands.isEmpty && commands.allSatisfy { $0.range(of: #"lidawake['"]? activity"#, options: .regularExpression) != nil }
    }

    static func quote(_ path: String) -> String {
        path.contains(" ") ? "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'" : path
    }

    static func read(_ file: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x09 || $0 == 0x0D }) { return [:] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadable(file.path)
        }
        return root
    }

    static func write(_ root: [String: Any], to file: URL) throws {
        let backup = file.appendingPathExtension("lidawake-backup")
        if FileManager.default.fileExists(atPath: file.path), !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: file, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (data + Data("\n".utf8)).write(to: file, options: .atomic)
    }
}
