import AppKit
import Combine
import serversHUDKit

/// Everything the panel shows: the last scan, the filter, which rows are new, kill progress.
/// Scans run on a background queue; results land on the main actor.
@MainActor
final class AppModel: ObservableObject {
    /// Every listening process from the last scan (unfiltered).
    @Published private(set) var servers: [Server] = []
    @Published var devOnly: Bool
    @Published var searchText = ""
    @Published var isCompact = false
    @Published private(set) var scanning = false
    @Published private(set) var lastScan: Date?
    /// pid -> when it (or a new port of it) appeared; rows glow for `highlightDuration`.
    @Published private(set) var recentlyAdded: [Int32: Date] = [:]
    @Published private(set) var killState: [Int32: KillState] = [:]
    @Published private(set) var message: Message?
    @Published private(set) var settings: ServersSettings
    /// Bumped to ask the search field to take focus.
    @Published var focusSearchToken = 0

    enum KillState: Equatable { case stopping, forceArmed }

    struct Message: Equatable {
        var text: String
        var error: Bool
        var id = UUID()
    }

    static let highlightDuration: TimeInterval = 6

    let settingsURL: URL
    let scanner = ServerScanner()
    private var snapshot: ServerSnapshot?
    private var waiters: [([Server]) -> Void] = []
    private var rescanRequested = false
    private var messageClear: DispatchWorkItem?

    /// Called after every scan (for `state` events).
    var onScan: (() -> Void)?

    init(settingsURL: URL) {
        self.settingsURL = settingsURL
        let loaded = ServersSettings.load(from: settingsURL)
        settings = loaded
        devOnly = loaded.devOnly
    }

    // MARK: - Filtering

    var filter: ServerFilter { ServerFilter(devOnly: devOnly, ignore: settings.ignoreList, query: searchText) }

    /// The rows the list shows.
    var visible: [Server] { filter.apply(servers) }

    /// Dev servers (dev-only, ignore list, no search): the badge.
    var devServers: [Server] { ServerFilter(devOnly: true, ignore: settings.ignoreList).apply(servers) }

    var badge: String { String(devServers.count) }

    /// `:3000 :5173 …` for `state`'s status.
    var status: String {
        let ports = devServers.compactMap(\.ports.first).map { ":\($0)" }
        if ports.isEmpty { return "no dev servers" }
        return ports.prefix(6).joined(separator: " ") + (ports.count > 6 ? " …" : "")
    }

    var hiddenCount: Int { servers.count - ServerFilter(devOnly: devOnly, ignore: settings.ignoreList).apply(servers).count }

    func isNew(_ server: Server, now: Date = Date()) -> Bool {
        guard let at = recentlyAdded[server.pid] else { return false }
        return now.timeIntervalSince(at) < Self.highlightDuration
    }

    // MARK: - Scanning

    /// Rescans (coalescing with a scan already running) and calls `completion` with the result.
    func refresh(completion: (([Server]) -> Void)? = nil) {
        if let completion { waiters.append(completion) }
        if scanning { rescanRequested = true; return }
        scanning = true
        let scanner = self.scanner
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = scanner.scan()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(result) }
            }
        }
    }

    private func apply(_ result: [Server]) {
        let now = Date()
        let next = ServerSnapshot(servers: result, takenAt: now)
        let diff = next.diff(since: snapshot)
        snapshot = next
        for s in diff.added { recentlyAdded[s.pid] = now }
        recentlyAdded = recentlyAdded.filter { now.timeIntervalSince($0.value) < Self.highlightDuration }
        let live = Set(result.map(\.pid))
        killState = killState.filter { live.contains($0.key) }
        let stopped = diff.removed.filter { r in !result.contains { $0.pid == r.pid } && ServerFilter(devOnly: devOnly).includes(r) }
        if !stopped.isEmpty {
            show("Stopped: " + stopped.map(\.entryName).joined(separator: "; "))
        }
        servers = result
        lastScan = now
        scanning = false
        let done = waiters
        waiters = []
        done.forEach { $0(result) }
        onScan?()
        if rescanRequested {
            rescanRequested = false
            refresh()
        }
    }

    // MARK: - Actions

    func open(port: Int) {
        if !ServerActions.open(port: port) { show("Cannot open port \(port)", error: true) }
    }

    func reveal(_ server: Server) {
        guard let cwd = server.cwd, ServerActions.reveal(cwd: cwd) else {
            show("No working directory for \(server.command)", error: true); return
        }
    }

    func copyURL(_ server: Server, port: Int? = nil) {
        guard let port = port ?? server.ports.first, ServerActions.copyURL(port: port) else { return }
        show("Copied http://localhost:\(port)")
    }

    /// SIGTERM. The row shows "Stopping…" until the process is gone from a scan.
    func kill(_ server: Server) {
        let outcome = ServerActions.kill(pid: server.pid, force: false, confirmed: false, servers: servers)
        report(outcome, server)
        if outcome.ok {
            killState[server.pid] = .stopping
            refreshSoon()
        }
    }

    /// A kill sent from elsewhere (the socket): show "Stopping…" on the row.
    func markStopping(_ pid: Int32) { killState[pid] = .stopping }

    /// First click arms Force for 3 s; the second sends SIGKILL.
    func forceKill(_ server: Server) {
        let pid = server.pid
        guard killState[pid] == .forceArmed else {
            killState[pid] = .forceArmed
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                MainActor.assumeIsolated {
                    if self?.killState[pid] == .forceArmed { self?.killState[pid] = nil }
                }
            }
            return
        }
        let outcome = ServerActions.kill(pid: pid, force: true, confirmed: true, servers: servers)
        report(outcome, server)
        killState[pid] = outcome.ok ? .stopping : nil
        if outcome.ok { refreshSoon() }
    }

    private func report(_ outcome: ServerActions.KillOutcome, _ server: Server) {
        if outcome.ok {
            show("\(outcome.signalName ?? "signal") → \(server.command) (\(server.pid))")
        } else {
            show("\(server.command) (\(server.pid)): \(outcome)", error: true)
        }
    }

    /// A few quick rescans so a killed server drops out without waiting for the timer.
    func refreshSoon() {
        for delay in [0.3, 1.0, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    // MARK: - Messages and settings

    func show(_ text: String, error: Bool = false) {
        message = Message(text: text, error: error)
        messageClear?.cancel()
        let task = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.message = nil } }
        messageClear = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: task)
    }

    func updateSettings(_ values: [String: String]) throws {
        let next = try settings.applying(values)
        try next.save(to: settingsURL)
        if values["devOnly"] != nil { devOnly = next.devOnly }
        settings = next
        onScan?()
    }
}
