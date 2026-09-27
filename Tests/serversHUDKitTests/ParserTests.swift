import XCTest
@testable import serversHUDKit

/// Parser tests for the scan. Fixtures captured live on macOS (Darwin 25.6.0) from
/// `lsof -nP -iTCP -sTCP:LISTEN -Fpcn`, `ps -o pid=,uid=,etime=,command= -p <pids>`, and
/// `lsof -a -p <pid> -d cwd -Fn`, so the parsers are exercised against real output.
final class ParserTests: XCTestCase {
    // MARK: lsof -Fpcn (listeners)

    static let lsofListenFixture = """
    p686
    crapportd
    f11
    n*:58371
    f15
    n*:58371
    f18
    n*:61880
    f20
    n*:61881
    p711
    cBeeper Desktop
    f20
    n127.0.0.1:56101
    f119
    n127.0.0.1:23373
    p763
    cControlCenter
    f9
    n*:7000
    f10
    n*:7000
    f11
    n*:5000
    f12
    n*:5000
    p89317
    cqemu-system-aarch64-headless
    f7
    n[::1]:56411
    f13
    n[::1]:56412
    f36
    n127.0.0.1:5555
    f37
    n[::1]:5555
    p31791
    cpython3.12
    f4
    n*:8765
    """

    func testLsofListenParse() {
        let listeners = LsofListenParser.parse(Self.lsofListenFixture)
        XCTAssertEqual(listeners.count, 15)
        XCTAssertEqual(listeners.first, RawListener(pid: 686, command: "rapportd", address: "*:58371"))
        XCTAssertTrue(listeners.contains(RawListener(pid: 711, command: "Beeper Desktop", address: "127.0.0.1:23373")))
        XCTAssertTrue(listeners.contains(RawListener(pid: 89317, command: "qemu-system-aarch64-headless", address: "[::1]:56412")))
    }

    func testPortFromAddress() {
        XCTAssertEqual(LsofListenParser.port(fromAddress: "*:8765"), 8765)
        XCTAssertEqual(LsofListenParser.port(fromAddress: "127.0.0.1:3000"), 3000)
        XCTAssertEqual(LsofListenParser.port(fromAddress: "[::1]:56412"), 56412)
        XCTAssertNil(LsofListenParser.port(fromAddress: "garbage"))
    }

    func testGroupDedupesPortsAndPreservesOrder() {
        let grouped = LsofListenParser.group(LsofListenParser.parse(Self.lsofListenFixture))
        XCTAssertEqual(grouped.map(\.pid), [686, 711, 763, 89317, 31791])
        let controlCenter = grouped.first { $0.pid == 763 }
        XCTAssertEqual(controlCenter?.command, "ControlCenter")
        XCTAssertEqual(controlCenter?.ports, [5000, 7000]) // dedup'd + sorted from 4 raw records
        XCTAssertEqual(grouped.first { $0.pid == 31791 }?.ports, [8765])
        XCTAssertEqual(grouped.first { $0.pid == 89317 }?.ports, [5555, 56411, 56412])
    }

    func testGroupEmptyInput() {
        XCTAssertEqual(LsofListenParser.group([]), [])
    }

    // MARK: ps -o pid=,uid=,etime=,command=

    static let psFixture = """
        1 0 09-02:33:10 /sbin/launchd
    54328 501    15:07:02 /opt/homebrew/Cellar/node@24/24.19.0/bin/node --require /Users/dev/projects/webapp/node_modules/.pnpm/tsx@4.23.13/node_modules/tsx/dist/preflight.cjs --import file:///Users/dev/projects/webapp/node_modules/.pnpm/tsx@4.23.13/node_modules/tsx/dist/loader.mjs src/server.ts
    89309 501    03:17:53 next-server (v16.3.4)
      686 501 09-02:30:41 /usr/libexec/rapportd
    31791 501       00:09 python3 -m http.server 8765
    """

    func testPsParse() {
        let entries = PsParser.parse(Self.psFixture)
        XCTAssertEqual(entries.count, 5)
        let launchd = entries.first { $0.pid == 1 }
        XCTAssertEqual(launchd?.uid, 0)
        XCTAssertEqual(launchd?.etime, "09-02:33:10")
        XCTAssertEqual(launchd?.command, "/sbin/launchd")
        let py = entries.first { $0.pid == 31791 }
        XCTAssertEqual(py?.uid, 501)
        XCTAssertEqual(py?.etime, "00:09")
        XCTAssertEqual(py?.command, "python3 -m http.server 8765")
        let node = entries.first { $0.pid == 54328 }
        XCTAssertEqual(node?.command, "/opt/homebrew/Cellar/node@24/24.19.0/bin/node --require /Users/dev/projects/webapp/node_modules/.pnpm/tsx@4.23.13/node_modules/tsx/dist/preflight.cjs --import file:///Users/dev/projects/webapp/node_modules/.pnpm/tsx@4.23.13/node_modules/tsx/dist/loader.mjs src/server.ts")
    }

    func testPsParseTrimsTrailingSpace() {
        // `next-server (v16.3.5) ` really does end in a space in ps output.
        XCTAssertEqual(PsParser.parse("47920   501    01:19:56 next-server (v16.3.5) ").first?.command, "next-server (v16.3.5)")
    }

    func testUptimeSecondsFormats() {
        XCTAssertEqual(PsParser.uptimeSeconds(etime: "00:09"), 9)
        XCTAssertEqual(PsParser.uptimeSeconds(etime: "15:07:02"), 15 * 3600 + 7 * 60 + 2)
        XCTAssertEqual(PsParser.uptimeSeconds(etime: "09-02:33:10"), 9 * 86_400 + 2 * 3600 + 33 * 60 + 10)
        XCTAssertEqual(PsParser.uptimeSeconds(etime: "5:01"), 301)
    }

    func testFormatUptime() {
        XCTAssertEqual(PsParser.formatUptime(seconds: 9), "9s")
        XCTAssertEqual(PsParser.formatUptime(seconds: 301), "5m")
        XCTAssertEqual(PsParser.formatUptime(seconds: 3900), "1h 5m")
        XCTAssertEqual(PsParser.formatUptime(seconds: 9 * 86_400 + 3600), "9d 1h")
    }

    // MARK: lsof -a -p <pids> -d cwd -Fpn

    func testLsofCwdParse() {
        XCTAssertEqual(LsofCwdParser.parse("p31791\nfcwd\nn/private/tmp/scratch/httpfixture"), "/private/tmp/scratch/httpfixture")
    }

    func testLsofCwdParseRoot() {
        XCTAssertEqual(LsofCwdParser.parse("p711\nfcwd\nn/"), "/")
    }

    func testLsofCwdParseMissing() {
        XCTAssertNil(LsofCwdParser.parse(""))
        XCTAssertNil(LsofCwdParser.parse("p123\n"))
    }

    func testLsofCwdParseAllMultiplePids() {
        let fixture = "p100\nfcwd\nn/Users/me/a\np200\nfcwd\nn/Users/me/b\n"
        XCTAssertEqual(LsofCwdParser.parseAll(fixture), [100: "/Users/me/a", 200: "/Users/me/b"])
    }

    func testLsofCwdIgnoresOtherDescriptors() {
        XCTAssertEqual(LsofCwdParser.parseAll("p100\nftxt\nn/bin/x\nfcwd\nn/Users/me/a\n"), [100: "/Users/me/a"])
    }
}
