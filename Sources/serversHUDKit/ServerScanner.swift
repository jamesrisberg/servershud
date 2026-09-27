import Foundation

/// Runs a tool and returns stdout ("" when it is missing or fails to start). lsof exits 1 when
/// some pids match nothing; stdout is still valid, so the status is ignored.
public typealias CommandRunner = @Sendable (_ path: String, _ args: [String]) -> String

public enum ShellRunner {
    public static let run: CommandRunner = { path, args in
        guard FileManager.default.isExecutableFile(atPath: path) else { return "" }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return ""
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// One `lsof -nP -iTCP -sTCP:LISTEN -Fpcn` call finds the listeners, then one `ps` call and
/// one `lsof -d cwd` call enrich every pid at once (the same three calls as devops' collector).
/// Synchronous and shells out: call off the main thread.
public struct ServerScanner: Sendable {
    public static let lsof = "/usr/sbin/lsof"
    public static let ps = "/bin/ps"

    public var run: CommandRunner
    public var currentUID: uid_t

    public init(run: @escaping CommandRunner = ShellRunner.run, currentUID: uid_t = getuid()) {
        self.run = run
        self.currentUID = currentUID
    }

    /// Every listening process, sorted by first port.
    public func scan() -> [Server] {
        let lsofOut = run(Self.lsof, ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"])
        let grouped = LsofListenParser.group(LsofListenParser.parse(lsofOut))
        guard !grouped.isEmpty else { return [] }

        let pidList = grouped.map { String($0.pid) }.joined(separator: ",")
        let psOut = run(Self.ps, ["-o", "pid=,uid=,etime=,command=", "-p", pidList])
        let psByPid = Dictionary(PsParser.parse(psOut).map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let cwdByPid = LsofCwdParser.parseAll(run(Self.lsof, ["-a", "-p", pidList, "-d", "cwd", "-Fpn"]))

        return grouped.map { g in
            let entry = psByPid[g.pid]
            let etime = entry?.etime ?? ""
            return Server(
                pid: g.pid, uid: entry?.uid, ports: g.ports, command: g.command,
                commandLine: Server.trimmedCommand(entry?.command ?? g.command),
                cwd: cwdByPid[g.pid], etime: etime,
                uptimeSeconds: etime.isEmpty ? 0 : PsParser.uptimeSeconds(etime: etime),
                currentUID: currentUID)
        }
        .sorted { ($0.ports.first ?? 0, $0.pid) < ($1.ports.first ?? 0, $1.pid) }
    }
}
