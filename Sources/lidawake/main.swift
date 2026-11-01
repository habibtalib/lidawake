import Foundation
import LidAwakeCore

let usage = """
lidawake \(LidAwakeVersion.string): keep your Mac awake with the lid closed (pmset -a disablesleep)

USAGE
  lidawake on [--for <duration>] [--battery-floor <percent>] [--wait]
  lidawake off
  lidawake status [--json]
  lidawake toggle
  lidawake install-permission
  lidawake uninstall-permission
  lidawake version

OPTIONS
  --for <duration>          Turn sleep back on after 90, 90m, 2h or 1h30m.
  --battery-floor <percent> Turn sleep back on when on battery at or below this level.
  --wait                    Stay in the foreground and enforce the timer and battery floor
                            yourself (otherwise the LidAwake menu bar app does it).

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

    init(_ argv: [String]) {
        command = argv.first ?? "status"
        var i = 1
        while i < argv.count {
            let arg = argv[i]
            switch arg {
            case "--for", "--battery-floor":
                guard i + 1 < argv.count else { fail("\(arg) needs a value") }
                options[arg] = argv[i + 1]
                i += 2
            case "--json", "--wait":
                flags.insert(arg)
                i += 1
            default:
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
        if let reason = Controller.enforce() {
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
        printStatus(Controller.status(), json: args.flags.contains("--json"))
    case "install-permission":
        try SudoersRule.install()
        print(SudoersRule.isInstalled() ? "Installed \(SudoersRule.path)." : "Installed, but sudo does not accept it yet. Check \(SudoersRule.path).")
    case "uninstall-permission":
        if PowerState.isSleepDisabled() { _ = try? Controller.turnOff() }
        try SudoersRule.uninstall()
        print("Removed \(SudoersRule.path).")
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
