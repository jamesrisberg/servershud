import XCTest
@testable import serversHUDKit

final class FrameworkTests: XCTestCase {
    private func detect(_ command: String, _ line: String) -> Framework? {
        Framework.detect(command: command, commandLine: line)
    }

    func testSpecificFrameworks() {
        XCTAssertEqual(detect("node", "next-server (v16.3.5)"), .next)
        XCTAssertEqual(detect("node", "node /Users/me/app/node_modules/.bin/next dev"), .next)
        XCTAssertEqual(detect("node", "node /Users/me/app/node_modules/.bin/vite --port 5173"), .vite)
        XCTAssertEqual(detect("node", "node /Users/me/app/node_modules/vite/bin/vite.js"), .vite)
        XCTAssertEqual(detect("node", "node node_modules/.bin/webpack serve"), .webpack)
        XCTAssertEqual(detect("node", "node node_modules/.bin/webpack-dev-server"), .webpack)
        XCTAssertEqual(detect("ruby", "ruby bin/rails server -p 3000"), .rails)
        XCTAssertEqual(detect("ruby", "puma 6.4.2 (tcp://localhost:3000) [app]"), .rails)
        XCTAssertEqual(detect("Python", "/usr/bin/python3 manage.py runserver 8000"), .django)
        XCTAssertEqual(detect("python3.12", "python3 -m flask run"), .flask)
        XCTAssertEqual(detect("python3.12", "/Users/me/.venv/bin/python /Users/me/.venv/bin/flask run"), .flask)
    }

    func testRuntimes() {
        XCTAssertEqual(detect("bun", "bun run dev.ts"), .node)
        XCTAssertEqual(detect("python3.12", "python3 -m http.server 8765"), .python)
        XCTAssertEqual(detect("uvicorn", "uvicorn app:main --reload"), .python)
        XCTAssertEqual(detect("main", "/var/folders/x/T/go-build123/b001/exe/main"), .go)
        XCTAssertEqual(detect("go", "go run ."), .go)
    }

    func testUnknown() {
        XCTAssertNil(detect("zed", "/Applications/Zed.app/Contents/MacOS/zed"))
        XCTAssertNil(detect("java", "/usr/bin/java -jar app.jar"))
        XCTAssertNil(detect("postgres", "/opt/homebrew/opt/postgresql@16/bin/postgres -D /opt/homebrew/var/postgresql@16"))
    }

    func testFrameworkKeepsAppBundleNodeDev() {
        // A node server launched from an app's bundled runtime still counts as dev.
        let s = server(pid: 10, command: "node", commandLine: "/Applications/Foo.app/Contents/MacOS/node server.js")
        XCTAssertTrue(s.isAppOrOS)
        XCTAssertTrue(s.isDev)
    }
}
