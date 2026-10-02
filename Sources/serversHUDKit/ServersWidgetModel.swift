import Foundation

/// What the `running` desktop widget shows: the dev servers the app already scanned (dev-only,
/// the ignore list applied), as a count with a status dot and the first few rows. Pure, so the
/// view and the tests share it.
public struct ServersWidgetModel: Equatable, Sendable {
    /// One listening dev server: a row you can click to open `http://localhost:<port>`.
    public struct Row: Equatable, Identifiable, Sendable {
        public var pid: Int32
        /// The first port; the one a click opens.
        public var port: Int
        /// Ports beyond the first.
        public var extraPorts: Int
        /// The working directory's name (`~` for the home directory), else the process name.
        public var project: String
        /// The guessed framework's title, else the process name.
        public var process: String
        public var uptime: String

        public var id: Int32 { pid }
        public var portText: String { extraPorts > 0 ? ":\(port) +\(extraPorts)" : ":\(port)" }
    }

    /// Dev servers, including any without a port a row could open.
    public var count: Int
    /// The first `maxRows` servers that have a port, in the scanner's (first port) order.
    public var rows: [Row]
    /// Servers with a port that did not fit in `rows`.
    public var hiddenCount: Int

    public var isRunning: Bool { count > 0 }
    public var countText: String {
        count == 0 ? "No dev servers" : "\(count) dev server\(count == 1 ? "" : "s")"
    }

    public init(servers: [Server], maxRows: Int = 4, home: String = NSHomeDirectory()) {
        count = servers.count
        let withPort = servers.filter { !$0.ports.isEmpty }
        rows = withPort.prefix(max(0, maxRows)).map { server in
            Row(pid: server.pid, port: server.ports[0], extraPorts: server.ports.count - 1,
                project: Self.projectName(cwd: server.cwd, command: server.command, home: home),
                process: server.framework?.title ?? server.command,
                uptime: server.uptime)
        }
        hiddenCount = withPort.count - rows.count
    }

    /// The last path component of the working directory, `~` for the home directory itself, the
    /// process name when there is no usable directory.
    public static func projectName(cwd: String?, command: String, home: String = NSHomeDirectory()) -> String {
        guard let cwd, !cwd.isEmpty else { return command }
        let trimmed = cwd.count > 1 && cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        if trimmed == "/" { return command }
        if trimmed == home { return "~" }
        let name = (trimmed as NSString).lastPathComponent
        return name.isEmpty ? command : name
    }
}
