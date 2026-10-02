import XCTest
@testable import serversHUDKit

/// What the `servers` desktop widget shows, from the dev servers the app already scanned.
final class WidgetModelTests: XCTestCase {
    func testEmptyIsIdle() {
        let model = ServersWidgetModel(servers: [])
        XCTAssertEqual(model.count, 0)
        XCTAssertFalse(model.isRunning)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.hiddenCount, 0)
        XCTAssertEqual(model.countText, "No dev servers")
    }

    func testCountAndRows() {
        let model = ServersWidgetModel(servers: [
            server(pid: 10, ports: [3000], command: "node", commandLine: "node vite", cwd: "/Users/me/shop", etime: "02:30:00"),
            server(pid: 11, ports: [5173, 24678], command: "node", commandLine: "node node_modules/.bin/vite", cwd: "/Users/me/blog", etime: "00:45"),
        ])
        XCTAssertEqual(model.count, 2)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.countText, "2 dev servers")
        XCTAssertEqual(model.rows.map(\.port), [3000, 5173])
        XCTAssertEqual(model.rows.map(\.project), ["shop", "blog"])
        XCTAssertEqual(model.rows[0].uptime, "2h 30m")
        XCTAssertEqual(model.rows[1].extraPorts, 1)
        XCTAssertEqual(model.rows[1].portText, ":5173 +1")
        XCTAssertEqual(model.rows[0].portText, ":3000")
        XCTAssertEqual(model.rows[1].process, "Vite", "the framework title when one is guessed")
    }

    func testSingularCount() {
        XCTAssertEqual(ServersWidgetModel(servers: [server(pid: 1)]).countText, "1 dev server")
    }

    func testRowsAreCappedAndTheRestCounted() {
        let servers = (0..<7).map { server(pid: Int32(100 + $0), ports: [3000 + $0]) }
        let model = ServersWidgetModel(servers: servers, maxRows: 4)
        XCTAssertEqual(model.count, 7)
        XCTAssertEqual(model.rows.count, 4)
        XCTAssertEqual(model.hiddenCount, 3)
        XCTAssertEqual(model.rows.map(\.port), [3000, 3001, 3002, 3003], "the first ports, as the panel orders them")
    }

    func testProjectNameFallsBackToTheProcess() {
        XCTAssertEqual(ServersWidgetModel.projectName(cwd: "/Users/me/app/", command: "node", home: "/Users/me"), "app")
        XCTAssertEqual(ServersWidgetModel.projectName(cwd: nil, command: "ruby", home: "/Users/me"), "ruby")
        XCTAssertEqual(ServersWidgetModel.projectName(cwd: "/", command: "ruby", home: "/Users/me"), "ruby")
        XCTAssertEqual(ServersWidgetModel.projectName(cwd: "/Users/me", command: "python3", home: "/Users/me"), "~")
    }

    func testProcessLabelIsTheCommandWithoutAFramework() {
        let rows = ServersWidgetModel(servers: [server(pid: 5, ports: [9000], command: "mystery", commandLine: "mystery --serve")]).rows
        XCTAssertEqual(rows.first?.process, "mystery")
    }

    func testNoPortYieldsNoRow() {
        let model = ServersWidgetModel(servers: [server(pid: 5, ports: [])])
        XCTAssertEqual(model.count, 1)
        XCTAssertTrue(model.rows.isEmpty, "a row is a port you can open")
    }
}
