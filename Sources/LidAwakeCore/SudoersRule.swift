import Foundation

/// Installs `/etc/sudoers.d/lidawake`, which lets one user run exactly
/// `pmset -a disablesleep 1` and `pmset -a disablesleep 0` as root without a password.
public enum SudoersRule {
    public static let path = "/etc/sudoers.d/lidawake"

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case invalidUser(String)
        case rejected(String)
        case cancelled

        public var description: String {
            switch self {
            case .invalidUser(let user): return "Refusing to write a sudoers rule for user name '\(user)'."
            case .rejected(let message): return "Could not install the permission: \(message)"
            case .cancelled: return "Cancelled."
            }
        }
    }

    /// macOS short user names: letters, digits, dot, underscore, hyphen. Anything else could alter the rule.
    public static func isSafeUserName(_ user: String) -> Bool {
        guard !user.isEmpty, user.count <= 64, user.first != "-" else { return false }
        return user.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }
    }

    public static func rule(for user: String) throws -> String {
        guard isSafeUserName(user) else { throw Failure.invalidUser(user) }
        return """
        # Installed by LidAwake. Allows only toggling lid-closed sleep. Remove with: lidawake uninstall-permission
        \(user) ALL=(root) NOPASSWD: \(PowerState.pmset) -a disablesleep 1, \(PowerState.pmset) -a disablesleep 0

        """
    }

    /// True when the rule file exists and sudo can run the pmset command without a password.
    /// (The file check stops a cached admin sudo timestamp from counting as installed.)
    public static func isInstalled() -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        guard let result = try? Shell.run(PowerState.sudo, ["-n", "-l", PowerState.pmset, "-a", "disablesleep", "1"]) else { return false }
        return result.status == 0
    }

    /// Validates the rule with visudo, then installs it with one administrator prompt.
    public static func install(user: String = NSUserName()) throws {
        let text = try rule(for: user)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("lidawake-sudoers-\(UUID().uuidString)")
        try text.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let check = try Shell.run("/usr/sbin/visudo", ["-c", "-f", temp.path])
        guard check.status == 0 else { throw Failure.rejected(check.stdout + check.stderr) }

        try runAsAdmin("/usr/bin/install -m 0440 -o root -g wheel \(quoted(temp.path)) \(quoted(path))",
                       prompt: "LidAwake needs to install a rule that lets it switch lid-closed sleep on and off.")
    }

    public static func uninstall() throws {
        try runAsAdmin("/bin/rm -f \(quoted(path))", prompt: "LidAwake will remove its sleep permission rule.")
    }

    /// Single-quotes a path for /bin/sh.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs a shell command as root through the standard macOS admin password dialog.
    private static func runAsAdmin(_ command: String, prompt: String) throws {
        func appleScriptString(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let script = "do shell script \(appleScriptString(command)) with prompt \(appleScriptString(prompt)) with administrator privileges"
        let result = try Shell.run("/usr/bin/osascript", ["-e", script])
        guard result.status == 0 else {
            if result.stderr.contains("-128") { throw Failure.cancelled }
            throw Failure.rejected(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
