import AppKit
import Foundation

/// What a row (or the socket, or the CLI) can do to a server.
public enum ServerActions {
    public enum KillOutcome: Equatable, Sendable, CustomStringConvertible {
        /// The signal was delivered (SIGTERM or SIGKILL).
        case sent(signal: Int32)
        /// SIGKILL asked for without `confirmed`: nothing was sent.
        case needsConfirmation
        /// The pid is not a listening server in the given scan: nothing was sent.
        case notAServer
        /// Never signalled: pid 0/1, this app, or another user's process.
        case refused(String)
        /// `kill(2)` failed with this errno (ESRCH: already gone).
        case failed(errno: Int32)

        public var ok: Bool { if case .sent = self { return true }; return false }

        public var signalName: String? {
            if case .sent(let s) = self { return s == SIGKILL ? "SIGKILL" : "SIGTERM" }
            return nil
        }

        public var description: String {
            switch self {
            case .sent(let s): return s == SIGKILL ? "sent SIGKILL" : "sent SIGTERM"
            case .needsConfirmation: return "force kill needs confirmation"
            case .notAServer: return "not a listening server"
            case .refused(let why): return why
            case .failed(let e): return e == ESRCH ? "no such process" : String(cString: strerror(e))
            }
        }
    }

    public typealias Signaller = (_ pid: Int32, _ signal: Int32) -> Int32

    /// Sends SIGTERM, or SIGKILL when `force` and `confirmed`, to `pid` — but only when `pid` is
    /// one of `servers` (a fresh scan) and belongs to the current user. Tests pass a fake
    /// `signaller`; the default is `kill(2)`.
    public static func kill(pid: Int32, force: Bool, confirmed: Bool, servers: [Server],
                            currentUID: uid_t = getuid(), ownPID: Int32 = getpid(),
                            signaller: Signaller = { Darwin.kill($0, $1) }) -> KillOutcome {
        guard pid > 1 else { return .refused("refusing to signal pid \(pid)") }
        guard pid != ownPID else { return .refused("refusing to signal serversHUD itself") }
        guard let server = servers.first(where: { $0.pid == pid }) else { return .notAServer }
        guard server.uid == currentUID else { return .refused("pid \(pid) belongs to another user") }
        if force && !confirmed { return .needsConfirmation }
        let signal = force ? SIGKILL : SIGTERM
        if signaller(pid, signal) == 0 { return .sent(signal: signal) }
        return .failed(errno: errno)
    }

    public static func isAlive(_ pid: Int32) -> Bool { Darwin.kill(pid, 0) == 0 || errno == EPERM }

    /// `http://localhost:<port>`, nil for ports outside 1...65535.
    public static func url(port: Int) -> URL? {
        guard (1...65535).contains(port) else { return nil }
        return URL(string: "http://localhost:\(port)")
    }

    @discardableResult
    public static func open(port: Int) -> Bool {
        guard let url = url(port: port) else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Shows the directory in Finder.
    @discardableResult
    public static func reveal(cwd: String) -> Bool {
        guard FileManager.default.fileExists(atPath: cwd) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd, isDirectory: true)])
        return true
    }

    @discardableResult
    public static func copyURL(port: Int, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let url = url(port: port) else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(url.absoluteString, forType: .string)
    }
}
