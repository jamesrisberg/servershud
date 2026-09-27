import XCTest
@testable import serversHUDKit

final class ServerTests: XCTestCase {
    func testSystemByUID() {
        XCTAssertTrue(server(pid: 2, command: "somedaemon", uid: 0).system)
        XCTAssertTrue(server(pid: 2, command: "somedaemon", uid: nil).system, "no ps row reads as not ours, like devops")
        XCTAssertFalse(server(pid: 2, command: "somedaemon").system)
    }

    func testSystemByDenyList() {
        XCTAssertTrue(server(pid: 686, ports: [58371], command: "rapportd").system)
    }

    func testDevServerIsNotSystem() {
        let py = server(pid: 31791, ports: [8765], command: "python3.12", commandLine: "python3 -m http.server 8765")
        XCTAssertFalse(py.system)
        XCTAssertTrue(py.isDev)
        XCTAssertEqual(py.framework, .python)
    }

    func testGUIAppsAreNotDev() {
        let zed = server(pid: 1341, command: "zed", commandLine: "/Applications/Zed.app/Contents/MacOS/zed")
        XCTAssertFalse(zed.system)
        XCTAssertTrue(zed.isAppOrOS)
        XCTAssertFalse(zed.isDev)
        let docker = server(pid: 5, command: "com.docker.backend",
                            commandLine: "/Applications/Docker.app/Contents/MacOS/com.docker.backend services")
        XCTAssertFalse(docker.isDev)
        XCTAssertFalse(server(pid: 6, command: "cupsd", commandLine: "/usr/sbin/cupsd -l").isDev)
    }

    func testToolchainInsideAnAppBundleStaysDev() {
        // Android Studio's bundled JDK runs Gradle daemons: not Contents/MacOS, so still listed.
        let java = server(pid: 55657, command: "java",
                          commandLine: "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java -cp x")
        XCTAssertTrue(java.isDev)
    }

    func testTrimmedCommandCollapsesWhitespaceAndCaps() {
        XCTAssertEqual(Server.trimmedCommand("node   src/server.ts\n--port 3000"), "node src/server.ts --port 3000")
        let trimmed = Server.trimmedCommand(String(repeating: "a", count: 250), maxLength: 10)
        XCTAssertEqual(trimmed.count, 10)
        XCTAssertTrue(trimmed.hasSuffix("…"))
    }

    func testURL() {
        XCTAssertEqual(server(pid: 9, ports: [5173, 24678]).url?.absoluteString, "http://localhost:5173")
        XCTAssertNil(server(pid: 9, ports: []).url)
        XCTAssertNil(ServerActions.url(port: 0))
        XCTAssertNil(ServerActions.url(port: 70000))
    }

    // MARK: devops --json servers

    /// The field names devops' ServersCollector writes into `details`.
    static let devopsDetailKeys: Set<String> = ["pid", "ports", "command", "commandLine", "cwd", "uptime",
                                                "uptimeSeconds", "etime", "uid", "system"]

    func testEntryMatchesDevopsShape() throws {
        let s = server(pid: 31791, ports: [8765, 8766], command: "python3.12",
                       commandLine: "python3 -m http.server 8765", cwd: "/tmp/x", etime: "00:09")
        let entry = s.entry
        XCTAssertEqual(entry["name"] as? String, "python3.12 :8765, :8766")
        XCTAssertEqual(entry["path"] as? String, "/tmp/x")
        XCTAssertEqual(entry["status"] as? String, "healthy")
        let details = try XCTUnwrap(entry["details"] as? [String: Any])
        XCTAssertTrue(Self.devopsDetailKeys.isSubset(of: Set(details.keys)))
        XCTAssertEqual(Set(details.keys).subtracting(Self.devopsDetailKeys), ["framework", "dev"])
        XCTAssertEqual(details["pid"] as? Int, 31791)
        XCTAssertEqual(details["ports"] as? [Int], [8765, 8766])
        XCTAssertEqual(details["uptime"] as? String, "9s")
        XCTAssertEqual(details["uptimeSeconds"] as? Int, 9)
        XCTAssertEqual(details["etime"] as? String, "00:09")
        XCTAssertEqual(details["uid"] as? Int, 501)
        XCTAssertEqual(details["system"] as? Bool, false)
        XCTAssertEqual(details["framework"] as? String, "python")
        XCTAssertEqual(details["dev"] as? Bool, true)
    }

    func testEntryNullsLikeDevops() throws {
        let s = server(pid: 7, command: "ghost", cwd: nil, uid: nil, etime: "")
        let details = try XCTUnwrap(s.entry["details"] as? [String: Any])
        for key in ["cwd", "uptime", "uptimeSeconds", "etime", "uid"] {
            XCTAssertTrue(details[key] is NSNull, key)
        }
        XCTAssertEqual(s.entry["path"] as? String, "")
    }

    func testDocument() throws {
        let data = ServersDocument.data([server(pid: 1234)], pretty: false, generatedAt: Date(timeIntervalSince1970: 0))
        let doc = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(doc["collector"] as? String, "servers")
        XCTAssertEqual(doc["generatedAt"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual((doc["entries"] as? [Any])?.count, 1)
    }
}
