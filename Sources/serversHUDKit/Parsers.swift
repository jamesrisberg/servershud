import Foundation

/// A single TCP listener bound to a pid, before grouping.
public struct RawListener: Equatable, Sendable {
    public var pid: Int32
    public var command: String
    public var address: String   // e.g. "*:8080", "127.0.0.1:3000", "[::1]:5555"

    public init(pid: Int32, command: String, address: String) {
        self.pid = pid
        self.command = command
        self.address = address
    }
}

/// Parses `lsof -nP -iTCP -sTCP:LISTEN -Fpcn` output: repeating records of a `p`
/// (pid) line, a `c` (command) line, then one `f`/`n` pair per listening socket.
public enum LsofListenParser {
    public static func parse(_ output: String) -> [RawListener] {
        var result: [RawListener] = []
        var pid: Int32?
        var command: String?
        for raw in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = raw.first else { continue }
            let value = String(raw.dropFirst())
            switch tag {
            case "p": pid = Int32(value); command = nil
            case "c": command = value
            case "n":
                if let pid, let command {
                    result.append(RawListener(pid: pid, command: command, address: value))
                }
            default: break
            }
        }
        return result
    }

    /// Port number from a listener address ("*:8080" -> 8080, "[::1]:5555" -> 5555).
    public static func port(fromAddress address: String) -> Int? {
        guard let idx = address.lastIndex(of: ":") else { return nil }
        return Int(address[address.index(after: idx)...])
    }
}

/// One process with all the ports it is listening on, in first-seen pid order.
public struct GroupedListener: Equatable, Sendable {
    public var pid: Int32
    public var command: String
    public var ports: [Int]
}

extension LsofListenParser {
    public static func group(_ listeners: [RawListener]) -> [GroupedListener] {
        var order: [Int32] = []
        var commands: [Int32: String] = [:]
        var ports: [Int32: Set<Int>] = [:]
        for l in listeners {
            if ports[l.pid] == nil {
                order.append(l.pid)
                ports[l.pid] = []
            }
            commands[l.pid] = l.command
            if let port = port(fromAddress: l.address) {
                ports[l.pid, default: []].insert(port)
            }
        }
        return order.map { pid in
            GroupedListener(pid: pid, command: commands[pid] ?? "", ports: (ports[pid] ?? []).sorted())
        }
    }
}

/// One row from `ps -o pid=,uid=,etime=,command= -p <pids>`.
public struct PsEntry: Equatable, Sendable {
    public var pid: Int32
    public var uid: uid_t
    public var etime: String
    public var command: String
}

public enum PsParser {
    private static let lineRegex = try! NSRegularExpression(pattern: #"^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.*)$"#)

    public static func parse(_ output: String) -> [PsEntry] {
        var entries: [PsEntry] = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            let range = NSRange(line.startIndex..., in: line)
            guard let match = lineRegex.firstMatch(in: line, range: range),
                  let pidRange = Range(match.range(at: 1), in: line),
                  let uidRange = Range(match.range(at: 2), in: line),
                  let etimeRange = Range(match.range(at: 3), in: line),
                  let commandRange = Range(match.range(at: 4), in: line),
                  let pid = Int32(line[pidRange]), let uid = uid_t(line[uidRange]) else { continue }
            let command = line[commandRange].trimmingCharacters(in: .whitespaces)
            entries.append(PsEntry(pid: pid, uid: uid, etime: String(line[etimeRange]), command: command))
        }
        return entries
    }

    /// `etime` is `[[dd-]hh:]mm:ss`. Returns total seconds.
    public static func uptimeSeconds(etime: String) -> Int {
        var days = 0
        var rest = Substring(etime)
        if let dash = rest.firstIndex(of: "-") {
            days = Int(rest[..<dash]) ?? 0
            rest = rest[rest.index(after: dash)...]
        }
        let parts = rest.split(separator: ":").compactMap { Int($0) }
        var seconds = 0
        switch parts.count {
        case 3: seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: seconds = parts[0] * 60 + parts[1]
        case 1: seconds = parts[0]
        default: break
        }
        return seconds + days * 86_400
    }

    public static func formatUptime(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

/// Parses `lsof -a -p <pid,pid,...> -d cwd -Fpn`: a `p` line per process, then `f`/`n`
/// pairs. One call covers every pid; only `cwd` descriptors are kept.
public enum LsofCwdParser {
    public static func parse(_ output: String) -> String? {
        parseAll(output).values.first
    }

    public static func parseAll(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var pid: Int32?
        var currentIsCwd = false
        for raw in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = raw.first else { continue }
            let value = String(raw.dropFirst())
            switch tag {
            case "p": pid = Int32(value); currentIsCwd = false
            case "f": currentIsCwd = (value == "cwd")
            case "n": if currentIsCwd, let pid, result[pid] == nil { result[pid] = value }
            default: break
            }
        }
        return result
    }
}
