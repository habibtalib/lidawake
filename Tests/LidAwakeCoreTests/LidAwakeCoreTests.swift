import Foundation
import XCTest
@testable import LidAwakeCore

final class PowerStateTests: XCTestCase {
    let on = """
    System-wide power settings:
     SleepDisabled\t\t1
    Currently in use:
     standby              1
     sleep                1 (sleep prevented by sharingd)
    """

    let off = """
    System-wide power settings:
     SleepDisabled\t\t0
    Currently in use:
     sleep                1
    """

    func testParsesSleepDisabled() {
        XCTAssertEqual(PowerState.parseSleepDisabled(on), true)
        XCTAssertEqual(PowerState.parseSleepDisabled(off), false)
        XCTAssertNil(PowerState.parseSleepDisabled("Currently in use:\n sleep 1\n"))
    }

    func testRootCommandIsExactlyPmsetDisablesleep() {
        XCTAssertEqual(PowerState.arguments(disable: true), ["-n", "/usr/bin/pmset", "-a", "disablesleep", "1"])
        XCTAssertEqual(PowerState.arguments(disable: false), ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"])
    }
}

final class SudoersRuleTests: XCTestCase {
    func testRuleAllowsOnlyTheTwoCommands() throws {
        let rule = try SudoersRule.rule(for: "habib")
        let lines = rule.split(separator: "\n").filter { !$0.hasPrefix("#") }
        XCTAssertEqual(lines, ["habib ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"])
    }

    func testRejectsUnsafeUserNames() {
        for name in ["", "-x", "a b", "root ALL=(ALL) ALL", "x\nALL", "a,b", "%admin", "a:b", String(repeating: "a", count: 65)] {
            XCTAssertThrowsError(try SudoersRule.rule(for: name), name)
        }
        for name in ["habib", "first.last", "dev_user-2"] {
            XCTAssertNoThrow(try SudoersRule.rule(for: name), name)
        }
    }

    func testQuotesShellPaths() {
        XCTAssertEqual(SudoersRule.quoted("/tmp/a b"), "'/tmp/a b'")
        XCTAssertEqual(SudoersRule.quoted("it's"), "'it'\\''s'")
    }
}

final class GuardTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testKeepsWithoutLimits() {
        let s = Session(startedAt: now, origin: .cli)
        XCTAssertEqual(Guard.evaluate(s, battery: BatteryStatus(percent: 5, onAC: false), now: now), .keep)
    }

    func testTimerEnds() {
        let s = Session(minutes: 30, batteryFloor: nil, origin: .app, now: now)
        XCTAssertEqual(Guard.evaluate(s, battery: .desktop, now: now.addingTimeInterval(29 * 60)), .keep)
        XCTAssertEqual(Guard.evaluate(s, battery: .desktop, now: now.addingTimeInterval(30 * 60)), .turnOff(.timerEnded))
    }

    func testBatteryFloorOnlyOnBattery() {
        let s = Session(minutes: nil, batteryFloor: 20, origin: .mcp, now: now)
        XCTAssertEqual(Guard.evaluate(s, battery: BatteryStatus(percent: 21, onAC: false), now: now), .keep)
        XCTAssertEqual(Guard.evaluate(s, battery: BatteryStatus(percent: 20, onAC: false), now: now), .turnOff(.batteryLow(20)))
        XCTAssertEqual(Guard.evaluate(s, battery: BatteryStatus(percent: 10, onAC: true), now: now), .keep)
        XCTAssertEqual(Guard.evaluate(s, battery: .desktop, now: now), .keep)
    }

    func testSessionIgnoresInvalidValues() {
        let s = Session(minutes: 0, batteryFloor: 150, origin: .cli, now: now)
        XCTAssertNil(s.deadline)
        XCTAssertNil(s.batteryFloor)
    }
}

final class StorageTests: XCTestCase {
    func testSessionRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lidawake-test-\(UUID().uuidString)/session.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let session = Session(startedAt: Date(timeIntervalSince1970: 100), deadline: Date(timeIntervalSince1970: 3700), batteryFloor: 15, origin: .widget)
        try SessionStore.save(session, to: url)
        XCTAssertEqual(SessionStore.load(from: url), session)
        try SessionStore.save(nil, to: url)
        XCTAssertNil(SessionStore.load(from: url))
    }

    func testWidgetRequestFreshness() {
        let now = Date()
        XCTAssertTrue(WidgetRequest(action: .toggle, createdAt: now.addingTimeInterval(-30)).isFresh(now: now))
        XCTAssertFalse(WidgetRequest(action: .toggle, createdAt: now.addingTimeInterval(-3600)).isFresh(now: now))
    }
}

final class DurationTests: XCTestCase {
    func testParses() {
        XCTAssertEqual(Duration.minutes("90"), 90)
        XCTAssertEqual(Duration.minutes("90m"), 90)
        XCTAssertEqual(Duration.minutes("2h"), 120)
        XCTAssertEqual(Duration.minutes("1h30m"), 90)
        XCTAssertEqual(Duration.minutes(" 1H "), 60)
        for bad in ["", "0", "-5", "h", "2x", "1h30", "abc"] {
            XCTAssertNil(Duration.minutes(bad), bad)
        }
    }

    func testFormats() {
        XCTAssertEqual(Duration.format(45), "45s")
        XCTAssertEqual(Duration.format(12 * 60), "12m")
        XCTAssertEqual(Duration.format(65 * 60), "1h 05m")
        XCTAssertEqual(Duration.format(-10), "0s")
    }
}
