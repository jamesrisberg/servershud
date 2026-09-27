import XCTest
@testable import serversHUDKit

final class FilterTests: XCTestCase {
    let all = [
        server(pid: 100, ports: [3000], command: "node", commandLine: "next-server (v16.3.5)", cwd: "/Users/me/shop"),
        server(pid: 101, ports: [8765], command: "python3.12", commandLine: "python3 -m http.server 8765", cwd: "/tmp/site"),
        server(pid: 102, ports: [7000, 5000], command: "ControlCenter",
               commandLine: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"),
        server(pid: 103, ports: [631], command: "cupsd", uid: 0),
        server(pid: 104, ports: [23373], command: "Beeper Desktop",
               commandLine: "/Applications/Beeper Desktop.app/Contents/MacOS/Beeper Desktop"),
        server(pid: 105, ports: [5432], command: "postgres", commandLine: "/opt/homebrew/bin/postgres -D x"),
    ]

    func testDevOnlyHidesSystemAndApps() {
        XCTAssertEqual(ServerFilter().apply(all).map(\.pid), [100, 101, 105])
        XCTAssertEqual(ServerFilter(devOnly: false).apply(all).count, all.count)
    }

    func testIgnoreListIsCaseInsensitiveAndOnlyInDevOnly() {
        let filter = ServerFilter(devOnly: true, ignore: ServerFilter.ignoreList(" Postgres ,,python3.12"))
        XCTAssertEqual(filter.apply(all).map(\.pid), [100])
        XCTAssertEqual(ServerFilter(devOnly: false, ignore: ["postgres"]).apply(all).count, all.count)
    }

    func testSearch() {
        XCTAssertEqual(ServerFilter(devOnly: false, query: ":8765").apply(all).map(\.pid), [101])
        XCTAssertEqual(ServerFilter(devOnly: false, query: "shop next").apply(all).map(\.pid), [100])
        XCTAssertEqual(ServerFilter(devOnly: false, query: "Next.js").apply(all).map(\.pid), [100])
        XCTAssertEqual(ServerFilter(devOnly: false, query: "104").apply(all).map(\.pid), [104])
        XCTAssertEqual(ServerFilter(devOnly: false, query: "nothing-like-this").apply(all), [])
    }

    func testIgnoreListParsing() {
        XCTAssertEqual(ServerFilter.ignoreList("a, b ,, c"), ["a", "b", "c"])
        XCTAssertEqual(ServerFilter.ignoreList(""), [])
    }
}

final class SnapshotTests: XCTestCase {
    func testFirstScanHasNoNews() {
        XCTAssertTrue(ServerSnapshot(servers: [server(pid: 1)]).diff(since: nil).isEmpty)
    }

    func testAddedAndRemoved() {
        let old = ServerSnapshot(servers: [server(pid: 10), server(pid: 11, ports: [4000])])
        let new = ServerSnapshot(servers: [server(pid: 11, ports: [4000]), server(pid: 12, ports: [5173])])
        let diff = new.diff(since: old)
        XCTAssertEqual(diff.added.map(\.pid), [12])
        XCTAssertEqual(diff.removed.map(\.pid), [10])
        XCTAssertEqual(diff.addedPIDs, [12])
    }

    func testNewPortCountsAsAdded() {
        let old = ServerSnapshot(servers: [server(pid: 10, ports: [5173])])
        let new = ServerSnapshot(servers: [server(pid: 10, ports: [5173, 24678])])
        let diff = new.diff(since: old)
        XCTAssertEqual(diff.added.map(\.pid), [10])
        XCTAssertEqual(diff.removed.map(\.pid), [10])
    }

    func testUnchanged() {
        let a = ServerSnapshot(servers: [server(pid: 10, etime: "00:01")])
        let b = ServerSnapshot(servers: [server(pid: 10, etime: "00:03")])
        XCTAssertTrue(b.diff(since: a).isEmpty, "uptime ticking is not a change")
    }
}
