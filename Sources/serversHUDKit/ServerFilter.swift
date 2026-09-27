import Foundation

/// What the list shows: dev-only (see `Server.isDev`), minus ignored process names, matching a
/// search. The badge counts `devOnly: true` with the ignore list and no search.
public struct ServerFilter: Equatable, Sendable {
    public var devOnly: Bool
    /// Process names (lsof's `command`) hidden in dev-only mode; compared case-insensitively.
    public var ignore: Set<String>
    public var query: String

    public init(devOnly: Bool = true, ignore: some Sequence<String> = [], query: String = "") {
        self.devOnly = devOnly
        self.ignore = Set(ignore.map { $0.lowercased() })
        self.query = query
    }

    /// Splits a comma-separated setting ("Beeper Desktop, zed").
    public static func ignoreList(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public func includes(_ server: Server) -> Bool {
        if devOnly {
            guard server.isDev, !ignore.contains(server.command.lowercased()) else { return false }
        }
        return matches(server)
    }

    /// Every whitespace-separated term must appear in the name, command line, cwd, framework,
    /// pid or a port (a leading ":" is allowed: ":3000").
    public func matches(_ server: Server) -> Bool {
        let terms = query.lowercased().split(separator: " ").map { String($0) }
        guard !terms.isEmpty else { return true }
        let haystack = ([server.command, server.commandLine, server.cwd ?? "", String(server.pid),
                         server.framework?.rawValue ?? "", server.framework?.title ?? ""]
                        + server.ports.map { ":\($0)" }).joined(separator: "\u{1}").lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }

    public func apply(_ servers: [Server]) -> [Server] { servers.filter(includes) }
}
