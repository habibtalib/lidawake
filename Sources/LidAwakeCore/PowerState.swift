import Foundation

/// Reads and changes the system-wide `disablesleep` flag.
public enum PowerState {
    public static let pmset = "/usr/bin/pmset"
    public static let sudo = "/usr/bin/sudo"

    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// The sudoers rule is missing, so sudo asked for a password.
        case permissionNotInstalled
        case commandFailed(String)

        public var description: String {
            switch self {
            case .permissionNotInstalled:
                return "LidAwake has no permission to run pmset yet. Run `lidawake install-permission` (or use the button in the menu bar app)."
            case .commandFailed(let message):
                return "pmset failed: \(message)"
            }
        }
    }

    /// Parses `pmset -g` output. Returns nil when the SleepDisabled line is missing.
    public static func parseSleepDisabled(_ output: String) -> Bool? {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == "SleepDisabled" {
                return parts[1] == "1"
            }
        }
        return nil
    }

    /// True when sleep is disabled (lid can close without sleeping). Needs no root.
    public static func isSleepDisabled() -> Bool {
        guard let result = try? Shell.run(pmset, ["-g"]) else { return false }
        return parseSleepDisabled(result.stdout) ?? false
    }

    /// The exact argument lists the sudoers rule allows. Nothing else is ever run as root.
    public static func arguments(disable: Bool) -> [String] {
        ["-n", pmset, "-a", "disablesleep", disable ? "1" : "0"]
    }

    /// Sets `pmset -a disablesleep` through the sudoers rule, without prompting.
    public static func setSleepDisabled(_ disable: Bool) throws {
        let result = try Shell.run(sudo, arguments(disable: disable))
        guard result.status == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.contains("password is required") || message.contains("not allowed") || message.contains("may not run") {
                throw Failure.permissionNotInstalled
            }
            throw Failure.commandFailed(message.isEmpty ? "exit \(result.status)" : message)
        }
    }
}
