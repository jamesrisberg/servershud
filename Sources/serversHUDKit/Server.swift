import Foundation

/// A deliberately short deny list of Apple system daemons that commonly listen on loopback
/// ports but are never dev servers. Shared with devops' `SYSTEM_DENY_LIST` and MacHUD's list;
/// keep them in sync.
public let systemDenyList: Set<String> = [
    "rapportd", "ControlCenter", "sharingd", "coreaudiod", "mDNSResponder",
    "cfprefsd", "UserEventAgent", "identityservicesd", "AirPlayXPCHelper",
]

/// One process with all the TCP ports it listens on, and everything the UI and JSON need.
public struct Server: Equatable, Identifiable, Sendable {
    public var pid: Int32
    /// nil when `ps` did not report the pid (it exited between the two calls).
    public var uid: uid_t?
    public var ports: [Int]
    /// Short process name, from lsof's `c` field.
    public var command: String
    /// Full command line, whitespace-collapsed and capped for display.
    public var commandLine: String
    public var cwd: String?
    public var etime: String
    public var uptimeSeconds: Int
    /// Another user's (root's) process or an Apple daemon on the deny list: the same rule as devops.
    public var system: Bool
    public var framework: Framework?

    public var id: Int32 { pid }

    public init(pid: Int32, uid: uid_t?, ports: [Int], command: String, commandLine: String, cwd: String?,
                etime: String, uptimeSeconds: Int, currentUID: uid_t = getuid()) {
        self.pid = pid
        self.uid = uid
        self.ports = ports
        self.command = command
        self.commandLine = commandLine
        self.cwd = cwd
        self.etime = etime
        self.uptimeSeconds = uptimeSeconds
        self.system = Self.isSystem(uid: uid, command: command, currentUID: currentUID)
        self.framework = Framework.detect(command: command, commandLine: commandLine)
    }

    public static func isSystem(uid: uid_t?, command: String, currentUID: uid_t) -> Bool {
        uid != currentUID || systemDenyList.contains(command)
    }

    /// A GUI app or OS binary that happens to listen on a port (Zed, Docker Desktop, Control
    /// Center): its executable is an app bundle's `Contents/MacOS/` binary or lives under
    /// `/System`, `/usr/libexec`, `/usr/sbin` or `/sbin`.
    public var isAppOrOS: Bool {
        let exe = commandLine.split(separator: " ").first.map(String.init) ?? commandLine
        if commandLine.contains(".app/Contents/MacOS/") { return true }
        return ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/"].contains { exe.hasPrefix($0) }
    }

    /// What dev-only mode keeps: the current user's processes that are not system daemons and
    /// not GUI apps, plus anything that looks like a known framework or runtime.
    public var isDev: Bool {
        guard !system else { return false }
        return framework != nil || !isAppOrOS
    }

    public var uptime: String { PsParser.formatUptime(seconds: uptimeSeconds) }

    /// `http://localhost:<port>` for the first port.
    public var url: URL? { ports.first.flatMap(ServerActions.url(port:)) }

    /// Collapse whitespace/newlines and cap length for display.
    public static func trimmedCommand(_ command: String, maxLength: Int = 200) -> String {
        let collapsed = command
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .joined(separator: " ")
        if collapsed.count <= maxLength { return collapsed }
        let cut = collapsed.prefix(maxLength - 1)
        return "\(cut)…"
    }

    // MARK: - JSON (devops --json servers)

    /// The entry name devops uses: `"<command> :3000, :3001"`.
    public var entryName: String {
        let ports = self.ports.map { ":\($0)" }.joined(separator: ", ")
        return "\(command) \(ports)".trimmingCharacters(in: .whitespaces)
    }

    /// `details` with devops' field names (`pid, ports, command, commandLine, cwd, uptime,
    /// uptimeSeconds, etime, uid, system`) plus serversHUD's `framework` and `dev`.
    public var details: [String: Any] {
        let hasEtime = !etime.isEmpty
        return [
            "pid": Int(pid), "ports": ports, "command": command, "commandLine": commandLine,
            "cwd": cwd as Any? ?? NSNull(),
            "uptime": hasEtime ? uptime : NSNull(),
            "uptimeSeconds": hasEtime ? uptimeSeconds : NSNull(),
            "etime": hasEtime ? etime : NSNull(),
            "uid": uid.map { Int($0) } as Any? ?? NSNull(),
            "system": system,
            "framework": framework?.rawValue as Any? ?? NSNull(),
            "dev": isDev,
        ]
    }

    /// One `entries[]` element of `devops --json servers`: `{name, path, status, details}`.
    public var entry: [String: Any] {
        ["name": entryName, "path": cwd ?? "", "status": "healthy", "details": details]
    }
}

/// The document `devops --json servers` prints: `{collector, generatedAt, entries}`.
public enum ServersDocument {
    public static func make(_ servers: [Server], generatedAt: Date = Date()) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return ["collector": "servers", "generatedAt": formatter.string(from: generatedAt),
                "entries": servers.map(\.entry)]
    }

    public static func data(_ servers: [Server], pretty: Bool = true, generatedAt: Date = Date()) -> Data {
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        return (try? JSONSerialization.data(withJSONObject: make(servers, generatedAt: generatedAt), options: options)) ?? Data()
    }
}
