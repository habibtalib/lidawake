import Foundation
import LidAwakeCore

let usage = """
lidawake \(LidAwakeVersion.string): keep your Mac awake with the lid closed (pmset -a disablesleep)

USAGE
  lidawake on [--for <duration>] [--battery-floor <percent>] [--wait]
  lidawake off
  lidawake status [--json]
  lidawake toggle
  lidawake keepalive <duration> [--reason <text>]
  lidawake release [--reason <text>]
  lidawake rules [--agent-mode on|off] [--agents-quiet <dur>|off] [--idle <dur>|off] [--network <dur>|off]
  lidawake hooks install|uninstall|status
  lidawake activity [--done]          (called by Claude Code hooks; reads the hook JSON on stdin)
  lidawake install-permission
  lidawake uninstall-permission
  lidawake version

OPTIONS
  --for <duration>          Turn sleep back on after 90, 90m, 2h or 1h30m.
  --battery-floor <percent> Turn sleep back on when on battery at or below this level.
  --wait                    Stay in the foreground and enforce the timer, battery floor and rules
                            yourself (otherwise the LidAwake menu bar app does it).
  --reason <text>           Who is holding the Mac awake (keepalive / release).

AGENT MODE
  With agent mode on, the menu bar app turns LidAwake on while Claude Code is working and off once it
  has been quiet. Activity comes from transcript writes (no setup), Claude Code hooks (`hooks install`)
  and keepalives from agents (MCP lidawake_keepalive or `lidawake keepalive`).

The first run needs `lidawake install-permission`: one admin prompt installs
/etc/sudoers.d/lidawake, which allows only `pmset -a disablesleep 1` and `0`.
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("lidawake: \(message)\n".utf8))
    exit(code)
}

struct Arguments {
    var command: String
    var options: [String: String] = [:]
    var flags: Set<String> = []
    var positional: [String] = []

    init(_ argv: [String]) {
        command = argv.first ?? "status"
        var i = 1
        while i < argv.count {
            let arg = argv[i]
            switch arg {
            case "--for", "--battery-floor", "--reason", "--agent-mode", "--agents-quiet", "--idle", "--network", "--settings":
                guard i + 1 < argv.count else { fail("\(arg) needs a value") }
                options[arg] = argv[i + 1]
                i += 2
            case "--json", "--wait", "--done":
                flags.insert(arg)
                i += 1
            default:
                if positional.isEmpty && !arg.hasPrefix("--") {
                    positional.append(arg)
                    i += 1
                    continue
                }
                fail("unknown option '\(arg)'\n\n\(usage)", code: 2)
            }
        }
    }
}

func appIsRunning() -> Bool {
    (try? Shell.run("/usr/bin/pgrep", ["-f", "LidAwake.app/Contents/MacOS/"]).status) == 0
}

func printStatus(_ status: Status, json: Bool) {
    if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: (try? encoder.encode(status)) ?? Data(), as: UTF8.self))
    } else {
        print(status.summary())
    }
}

/// Blocks until the session ends, checking every 15 seconds. Ctrl-C turns sleep back on.
func waitForSession() -> Never {
    signal(SIGINT, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    source.setEventHandler {
        _ = try? Controller.turnOff()
        print("\nSleep is back on.")
        exit(0)
    }
    source.resume()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: 15)
    timer.setEventHandler {
        if case .turnOff(let reason) = Controller.enforce() {
            print("\(reason) Sleep is back on.")
            exit(0)
        }
        if !PowerState.isSleepDisabled() { exit(0) }
    }
    timer.resume()
    dispatchMain()
}

let args = Arguments(Array(CommandLine.arguments.dropFirst()))

do {
    switch args.command {
    case "on":
        var minutes: Int?
        if let text = args.options["--for"] {
            guard let m = Duration.minutes(text) else { fail("can't read duration '\(text)' (try 90m, 2h, 1h30m)") }
            minutes = m
        }
        var floor: Int?
        if let text = args.options["--battery-floor"] {
            guard let n = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% "))), (1...99).contains(n) else {
                fail("--battery-floor must be 1–99")
            }
            floor = n
        }
        let status = try Controller.turnOn(minutes: minutes, batteryFloor: floor, origin: .cli)
        printStatus(status, json: args.flags.contains("--json"))
        if args.flags.contains("--wait") {
            waitForSession()
        } else if (minutes != nil || floor != nil) && !appIsRunning() {
            print("Note: the LidAwake app is not running, so nothing will turn sleep back on automatically. Start the app or use --wait.")
        }
    case "off":
        printStatus(try Controller.turnOff(), json: args.flags.contains("--json"))
    case "toggle":
        let status = PowerState.isSleepDisabled() ? try Controller.turnOff() : try Controller.turnOn(origin: .cli)
        printStatus(status, json: args.flags.contains("--json"))
    case "status":
        let status = Controller.status()
        printStatus(status, json: args.flags.contains("--json"))
        if !args.flags.contains("--json") {
            let rules = AutoRules.load()
            let activity = Controller.snapshot()
            let now = Date()
            print("Rules: \(rules.summary).")
            let busy = activity.agentBusy(at: now, window: rules.busyWindow)
            let last = activity.lastAgentActivity(at: now).map { "last activity \(Duration.format(now.timeIntervalSince($0))) ago" } ?? "no agent activity seen"
            print("Agents: \(busy ? "working" : "quiet"), \(last); \(activity.store.activeLeases().count) keepalive(s); hooks \(ClaudeHooks.isInstalled() ? "installed" : "not installed").")
        }
    case "install-permission":
        try SudoersRule.install()
        print(SudoersRule.isInstalled() ? "Installed \(SudoersRule.path)." : "Installed, but sudo does not accept it yet. Check \(SudoersRule.path).")
    case "uninstall-permission":
        if PowerState.isSleepDisabled() { _ = try? Controller.turnOff() }
        try SudoersRule.uninstall()
        print("Removed \(SudoersRule.path).")
    case "activity":
        // Called by Claude Code hooks: never fail or slow down the hook.
        var sessionId = "claude"
        if isatty(STDIN_FILENO) == 0 {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = json["session_id"] as? String, !id.isEmpty {
                sessionId = id
            }
        }
        try? Controller.recordHook(session: sessionId, done: args.flags.contains("--done"))
        exit(0)
    case "keepalive":
        guard let text = args.positional.first, let minutes = Duration.minutes(text) else { fail("usage: lidawake keepalive <duration> [--reason text]") }
        printStatus(try Controller.keepalive(minutes: minutes, reason: args.options["--reason"] ?? "cli", source: .cli), json: args.flags.contains("--json"))
        if !appIsRunning() { print("Note: start the LidAwake app so the keepalive and rules are enforced.") }
    case "release":
        printStatus(try Controller.release(reason: args.options["--reason"]), json: args.flags.contains("--json"))
    case "rules":
        var rules = AutoRules.load()
        func minutes(_ key: String) -> Int? {
            guard let text = args.options[key] else { return nil }
            if text == "off" || text == "0" { return 0 }
            guard let m = Duration.minutes(text) else { fail("can't read \(key) '\(text)' (try 10m, 1h or off)") }
            return m
        }
        if let mode = args.options["--agent-mode"] {
            guard mode == "on" || mode == "off" else { fail("--agent-mode must be on or off") }
            rules.agentMode = mode == "on"
        }
        if let m = minutes("--agents-quiet") {
            if rules.agentMode || m == 0 { rules.agentQuietMinutes = max(m, 1) }
            rules.offWhenAgentsQuietMinutes = m
        }
        if let m = minutes("--idle") { rules.offWhenIdleMinutes = m }
        if let m = minutes("--network") { rules.offWhenNetworkDownMinutes = m }
        try rules.save()
        Signal.post(.activity)
        print("Rules: \(rules.summary).")
    case "hooks":
        switch args.positional.first ?? "status" {
        case "install":
            try ClaudeHooks.install(command: ClaudeHooks.defaultCommand())
            for file in ClaudeHooks.settingsFiles() { print("Installed hooks in \(file.path)") }
        case "uninstall":
            try ClaudeHooks.uninstall()
            print("Removed LidAwake hooks.")
        default:
            for file in ClaudeHooks.settingsFiles() {
                print("\(ClaudeHooks.isInstalled(files: [file]) ? "installed" : "missing  ")  \(file.path)")
            }
        }
    case "version", "--version", "-v":
        print(LidAwakeVersion.string)
    case "help", "--help", "-h":
        print(usage)
    default:
        fail("unknown command '\(args.command)'\n\n\(usage)", code: 2)
    }
} catch {
    fail("\(error)")
}
