import AppKit
import XCTest
@testable import serversHUDKit

/// Kill is only ever exercised against a fake signaller here: nothing is signalled.
final class ActionsTests: XCTestCase {
    final class Recorder {
        var calls: [(Int32, Int32)] = []
        var result: Int32 = 0
        lazy var signaller: ServerActions.Signaller = { [unowned self] pid, sig in self.calls.append((pid, sig)); return self.result }
    }

    let servers = [server(pid: 4242, ports: [8765]), server(pid: 77, ports: [631], command: "cupsd", uid: 0)]

    func testTermNeedsNoConfirmation() {
        let r = Recorder()
        let outcome = ServerActions.kill(pid: 4242, force: false, confirmed: false, servers: servers,
                                         currentUID: 501, ownPID: 1000, signaller: r.signaller)
        XCTAssertEqual(outcome, .sent(signal: SIGTERM))
        XCTAssertEqual(outcome.signalName, "SIGTERM")
        XCTAssertEqual(r.calls.map(\.0), [4242])
        XCTAssertEqual(r.calls.map(\.1), [SIGTERM])
    }

    func testForceNeedsConfirmation() {
        let r = Recorder()
        XCTAssertEqual(ServerActions.kill(pid: 4242, force: true, confirmed: false, servers: servers,
                                          currentUID: 501, ownPID: 1000, signaller: r.signaller), .needsConfirmation)
        XCTAssertTrue(r.calls.isEmpty)
        XCTAssertEqual(ServerActions.kill(pid: 4242, force: true, confirmed: true, servers: servers,
                                          currentUID: 501, ownPID: 1000, signaller: r.signaller), .sent(signal: SIGKILL))
        XCTAssertEqual(r.calls.map(\.1), [SIGKILL])
    }

    func testRefusals() {
        let r = Recorder()
        func kill(_ pid: Int32) -> ServerActions.KillOutcome {
            ServerActions.kill(pid: pid, force: false, confirmed: true, servers: servers + [server(pid: 1000)],
                               currentUID: 501, ownPID: 1000, signaller: r.signaller)
        }
        XCTAssertEqual(kill(99999), .notAServer)
        XCTAssertEqual(kill(1), .refused("refusing to signal pid 1"))
        XCTAssertEqual(kill(0), .refused("refusing to signal pid 0"))
        XCTAssertEqual(kill(1000), .refused("refusing to signal serversHUD itself"))
        XCTAssertEqual(kill(77), .refused("pid 77 belongs to another user"))
        XCTAssertTrue(r.calls.isEmpty)
    }

    func testCopyURL() {
        let pb = NSPasteboard(name: NSPasteboard.Name("servershud.tests.\(UUID().uuidString)"))
        XCTAssertTrue(ServerActions.copyURL(port: 5173, to: pb))
        XCTAssertEqual(pb.string(forType: .string), "http://localhost:5173")
        pb.releaseGlobally()
    }
}

final class ScannerTests: XCTestCase {
    /// The three calls the scanner makes, answered from fixtures.
    func testScanJoinsTheThreeCalls() {
        let calls = Calls()
        let runner: CommandRunner = { path, args in
            calls.append("\(path) \(args.joined(separator: " "))")
            if path == ServerScanner.ps { return ParserTests.psFixture + "\n  711 501 1-00:00:00 /Applications/Beeper Desktop.app/Contents/MacOS/Beeper Desktop" }
            if args.contains("cwd") { return "p31791\nfcwd\nn/tmp/site\np686\nfcwd\nn/\n" }
            return ParserTests.lsofListenFixture
        }
        let servers = ServerScanner(run: runner, currentUID: 501).scan()
        XCTAssertEqual(calls.all.count, 3)
        XCTAssertEqual(calls.all[0], "/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN -Fpcn")
        XCTAssertEqual(calls.all[1], "/bin/ps -o pid=,uid=,etime=,command= -p 686,711,763,89317,31791")
        XCTAssertEqual(calls.all[2], "/usr/sbin/lsof -a -p 686,711,763,89317,31791 -d cwd -Fpn")
        // Sorted by first port.
        XCTAssertEqual(servers.map(\.pid), [763, 89317, 31791, 711, 686])
        let py = servers.first { $0.pid == 31791 }
        XCTAssertEqual(py?.cwd, "/tmp/site")
        XCTAssertEqual(py?.uptimeSeconds, 9)
        XCTAssertEqual(py?.framework, .python)
        XCTAssertEqual(py?.isDev, true)
        // No ps row (763, 89317 here): unknown uid reads as system, as in devops.
        XCTAssertEqual(servers.first { $0.pid == 763 }?.system, true)
        XCTAssertNil(servers.first { $0.pid == 763 }?.uid)
        XCTAssertEqual(ServerFilter().apply(servers).map(\.pid), [31791])
    }

    func testEmptyScanMakesOneCall() {
        let calls = Calls()
        let servers = ServerScanner(run: { path, args in calls.append(path); return "" }, currentUID: 501).scan()
        XCTAssertEqual(servers, [])
        XCTAssertEqual(calls.all.count, 1)
    }

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [String] = []
        func append(_ s: String) { lock.lock(); calls.append(s); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return calls }
    }
}

final class SettingsTests: XCTestCase {
    func testDefaults() {
        let s = ServersSettings()
        XCTAssertEqual(s.refreshInterval, 2)
        XCTAssertTrue(s.devOnly)
        XCTAssertEqual(s.ignoreList, [])
    }

    func testApplyValidatesAll() throws {
        let s = try ServersSettings().applying(["refreshInterval": "5", "devOnly": "false", "ignore": "zed,  Beeper Desktop"])
        XCTAssertEqual(s.refreshInterval, 5)
        XCTAssertFalse(s.devOnly)
        XCTAssertEqual(s.ignore, "zed, Beeper Desktop")
        XCTAssertEqual(s.ignoreList, ["zed", "Beeper Desktop"])
        XCTAssertThrowsError(try ServersSettings().applying(["refreshInterval": "0"]))
        XCTAssertThrowsError(try ServersSettings().applying(["devOnly": "maybe"]))
        XCTAssertThrowsError(try ServersSettings().applying(["nope": "1"]))
    }

    func testRoundTripAndPartialFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("servershud-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        var s = ServersSettings()
        s.refreshInterval = 7
        try s.save(to: url)
        XCTAssertEqual(ServersSettings.load(from: url), s)
        try Data(#"{"ignore": "zed", "refreshInterval": 500}"#.utf8).write(to: url)
        let partial = ServersSettings.load(from: url)
        XCTAssertEqual(partial.ignore, "zed")
        XCTAssertEqual(partial.refreshInterval, 60, "clamped")
        XCTAssertTrue(partial.devOnly)
    }

    func testOneUndecodableValueKeepsTheOtherSavedSettings() throws {
        let json = #"{"refreshInterval": "often", "devOnly": false, "ignore": "zed"}"#
        let s = try JSONDecoder().decode(ServersSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.refreshInterval, ServersSettings().refreshInterval)
        XCTAssertEqual(s.devOnly, false)
        XCTAssertEqual(s.ignore, "zed")
    }
}
