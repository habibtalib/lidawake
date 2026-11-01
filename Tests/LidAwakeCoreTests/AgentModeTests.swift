import Foundation
import XCTest
@testable import LidAwakeCore

final class AgentGuardTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var rules = AutoRules(agentMode: true, agentQuietMinutes: 10, offWhenAgentsQuietMinutes: 15,
                          offWhenIdleMinutes: 30, offWhenNetworkDownMinutes: 10, busyWindowMinutes: 3)

    func snapshot(lastWrite: TimeInterval? = nil, idle: TimeInterval = 0, networkDown: TimeInterval? = nil,
                  store: ActivityStore = ActivityStore()) -> ActivitySnapshot {
        ActivitySnapshot(lastTranscriptWrite: lastWrite.map { now.addingTimeInterval(-$0) }, store: store,
                         userIdleSeconds: idle, networkDownSince: networkDown.map { now.addingTimeInterval(-$0) })
    }

    func session(_ origin: Origin, startedAgo: TimeInterval = 3600) -> Session {
        Session(startedAt: now.addingTimeInterval(-startedAgo), origin: origin)
    }

    func testAgentModeTurnsOnWhenBusy() {
        let d = Guard.evaluate(session: nil, battery: .desktop, activity: snapshot(lastWrite: 20), rules: rules, now: now)
        XCTAssertEqual(d, .turnOn(.agentBusy))
    }

    func testNoTurnOnWhenAgentModeOffOrQuiet() {
        var off = rules
        off.agentMode = false
        XCTAssertEqual(Guard.evaluate(session: nil, battery: .desktop, activity: snapshot(lastWrite: 20), rules: off, now: now), .keep)
        XCTAssertEqual(Guard.evaluate(session: nil, battery: .desktop, activity: snapshot(lastWrite: 600), rules: rules, now: now), .keep)
    }

    func testNoTurnOnBelowBatteryFloor() {
        let low = BatteryStatus(percent: 15, onAC: false)
        XCTAssertEqual(Guard.evaluate(session: nil, battery: low, activity: snapshot(lastWrite: 5), rules: rules, batteryFloor: 20, now: now), .keep)
    }

    func testAgentSessionEndsAfterQuiet() {
        XCTAssertEqual(Guard.evaluate(session: session(.agent), battery: .desktop, activity: snapshot(lastWrite: 9 * 60), rules: rules, now: now), .keep)
        XCTAssertEqual(Guard.evaluate(session: session(.agent), battery: .desktop, activity: snapshot(lastWrite: 11 * 60), rules: rules, now: now),
                       .turnOff(.agentsQuiet(11)))
    }

    func testManualSessionUsesItsOwnQuietRule() {
        XCTAssertEqual(Guard.evaluate(session: session(.app), battery: .desktop, activity: snapshot(lastWrite: 11 * 60), rules: rules, now: now), .keep)
        XCTAssertEqual(Guard.evaluate(session: session(.app), battery: .desktop, activity: snapshot(lastWrite: 16 * 60), rules: rules, now: now),
                       .turnOff(.agentsQuiet(16)))
        var never = rules
        never.offWhenAgentsQuietMinutes = 0
        never.offWhenIdleMinutes = 0
        XCTAssertEqual(Guard.evaluate(session: session(.app), battery: .desktop, activity: snapshot(lastWrite: 5 * 3600), rules: never, now: now), .keep)
    }

    func testQuietCountsFromSessionStart() {
        // Turned on by hand 2 minutes ago, no agent activity for hours: not cut off straight away.
        XCTAssertEqual(Guard.evaluate(session: session(.app, startedAgo: 120), battery: .desktop, activity: snapshot(lastWrite: 5 * 3600), rules: rules, now: now), .keep)
    }

    func testIdleNeedsNoInputAndNoAgents() {
        var r = rules
        r.offWhenAgentsQuietMinutes = 0
        XCTAssertEqual(Guard.evaluate(session: session(.app), battery: .desktop, activity: snapshot(lastWrite: 60, idle: 3600), rules: r, now: now), .keep)
        XCTAssertEqual(Guard.evaluate(session: session(.app), battery: .desktop, activity: snapshot(lastWrite: 3600, idle: 31 * 60), rules: r, now: now),
                       .turnOff(.idle(31)))
        XCTAssertEqual(Guard.evaluate(session: session(.app), battery: .desktop, activity: snapshot(lastWrite: 3600, idle: 60), rules: r, now: now), .keep)
    }

    func testNetworkDown() {
        XCTAssertEqual(Guard.evaluate(session: session(.app), battery: .desktop, activity: snapshot(lastWrite: 10, networkDown: 9 * 60), rules: rules, now: now), .keep)
        XCTAssertEqual(Guard.evaluate(session: session(.app), battery: .desktop, activity: snapshot(lastWrite: 10, networkDown: 12 * 60), rules: rules, now: now),
                       .turnOff(.networkDown(12)))
    }

    func testTimerAndBatteryStillWinAndLeasesHold() {
        let timed = Session(startedAt: now.addingTimeInterval(-3600), deadline: now.addingTimeInterval(-1), origin: .app)
        XCTAssertEqual(Guard.evaluate(session: timed, battery: .desktop, activity: snapshot(lastWrite: 5), rules: rules, now: now), .turnOff(.timerEnded))

        var store = ActivityStore()
        store.hold(reason: "deploy", minutes: 20, source: .mcp, at: now)
        XCTAssertEqual(Guard.evaluate(session: session(.app), battery: .desktop, activity: snapshot(lastWrite: 5 * 3600, idle: 5 * 3600, store: store), rules: rules, now: now), .keep)
    }
}

final class ActivityStoreTests: XCTestCase {
    func testRoundTripLeasesAndPrune() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lidawake-act-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()
        try ActivityStore.update(at: url, now: now) {
            $0.ping(session: "s1", at: now)
            $0.hold(reason: "Build", minutes: 10, source: .cli, at: now)
            $0.ping(session: "old", at: now.addingTimeInterval(-2 * 86400))
        }
        var store = ActivityStore.load(from: url)
        XCTAssertNotNil(store.sessions["s1"])
        XCTAssertNil(store.sessions["old"])
        XCTAssertEqual(store.activeLeases(at: now).map(\.reason), ["Build"])
        XCTAssertTrue(store.activeLeases(at: now.addingTimeInterval(11 * 60)).isEmpty)
        store.release(reason: "build")
        XCTAssertTrue(store.leases.isEmpty)
    }

    func testDoneHookIsNotWorking() {
        let now = Date()
        var store = ActivityStore()
        store.ping(session: "a", at: now.addingTimeInterval(-30))
        store.ping(session: "b", done: true, at: now.addingTimeInterval(-30))
        let snap = ActivitySnapshot(store: store)
        XCTAssertEqual(snap.workingSessions(at: now, window: 180), 1)
        XCTAssertTrue(snap.agentBusy(at: now, window: 180))
        store.ping(session: "a", done: true, at: now)
        XCTAssertFalse(ActivitySnapshot(store: store).agentBusy(at: now, window: 180))
    }

    func testRulesDecodeDefaults() throws {
        let rules = try JSONDecoder().decode(AutoRules.self, from: Data(#"{"agentMode":true}"#.utf8))
        XCTAssertTrue(rules.agentMode)
        XCTAssertEqual(rules.offWhenIdleMinutes, AutoRules.default.offWhenIdleMinutes)
    }
}

final class TranscriptScannerTests: XCTestCase {
    func testNewestWriteAndDedup() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("lidawake-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let projA = home.appendingPathComponent(".claude/projects/p1")
        let projB = home.appendingPathComponent(".claude-profiles/work/projects/p2")
        try FileManager.default.createDirectory(at: projA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projB, withIntermediateDirectories: true)
        // a profile whose projects folder is a symlink to ~/.claude/projects is counted once
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude-profiles/link"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".claude-profiles/link/projects"),
                                                   withDestinationURL: home.appendingPathComponent(".claude/projects"))
        let old = projA.appendingPathComponent("a.jsonl"), new = projB.appendingPathComponent("b.jsonl")
        try Data("{}\n".utf8).write(to: old)
        try Data("{}\n".utf8).write(to: new)
        let t1 = Date(timeIntervalSince1970: 1_700_000_000), t2 = Date(timeIntervalSince1970: 1_700_000_500)
        try FileManager.default.setAttributes([.modificationDate: t1], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: t2], ofItemAtPath: new.path)

        let roots = TranscriptScanner.roots(home: home, environment: [:])
        XCTAssertEqual(roots.count, 2)
        XCTAssertEqual(TranscriptScanner.lastWrite(roots: roots), t2)
    }
}

final class ClaudeHooksTests: XCTestCase {
    func testMergeIdempotentAndUninstall() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lidawake-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let existing = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        try Data(existing.utf8).write(to: file)

        try ClaudeHooks.install(command: "/Users/x/.local/bin/lidawake", files: [file])
        try ClaudeHooks.install(command: "/Users/x/.local/bin/lidawake", files: [file])
        XCTAssertTrue(ClaudeHooks.isInstalled(files: [file]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.appendingPathExtension("lidawake-backup").path))

        let root = try ClaudeHooks.read(file)
        XCTAssertEqual(root["model"] as? String, "opus")
        let stop = ClaudeHooks.entries(root, "Stop")
        XCTAssertEqual(stop.count, 2, "user's own Stop hook kept, ours added once")
        XCTAssertEqual(ClaudeHooks.entries(root, "PreToolUse").count, 1)
        let ours = stop.first(where: ClaudeHooks.isOurs)?["hooks"] as? [[String: Any]]
        XCTAssertEqual(ours?.first?["command"] as? String, "/Users/x/.local/bin/lidawake activity --done")

        try ClaudeHooks.uninstall(files: [file])
        let after = try ClaudeHooks.read(file)
        XCTAssertFalse(ClaudeHooks.isInstalled(files: [file]))
        XCTAssertEqual(ClaudeHooks.entries(after, "Stop").count, 1)
        XCTAssertNil((after["hooks"] as? [String: Any])?["PreToolUse"])
    }

    func testRefusesInvalidJSON() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lidawake-bad-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{ not json".utf8).write(to: file)
        XCTAssertThrowsError(try ClaudeHooks.install(command: "lidawake", files: [file]))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{ not json")
    }
}
