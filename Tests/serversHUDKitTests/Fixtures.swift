import Foundation
@testable import serversHUDKit

/// Builds a `Server` for uid 501 (the "current user" in these tests).
func server(pid: Int32, ports: [Int] = [3000], command: String = "node", commandLine: String? = nil,
            cwd: String? = "/Users/me/app", uid: uid_t? = 501, etime: String = "01:00") -> Server {
    Server(pid: pid, uid: uid, ports: ports, command: command, commandLine: commandLine ?? command, cwd: cwd,
           etime: etime, uptimeSeconds: PsParser.uptimeSeconds(etime: etime), currentUID: 501)
}
