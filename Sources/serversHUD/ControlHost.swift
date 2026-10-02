import AppKit
import HUDKit
import serversHUDKit

/// serversHUD's side of the MacHUD contract: serves the control socket at
/// `~/Library/Application Support/MacHUD/sockets/servershud.sock` through HUDKit's router.
/// See docs/CONTRACT.md for the verbs.
@MainActor
final class ControlHost: HUDPanelHost {
    static let panelID = "servers"
    /// The desktop widget type: a `kind: widget` manifest panel, served by `HUDWidgetHost` (see ServersWidget.swift).
    static let widgetType = "running"
    static let actions = ["show", "hide", "toggle", "refresh", "kill", "open", "list"]
    static let verbs = ["show", "hide", "toggle", "frame", "mode", "refresh", "kill", "open", "list"]

    /// Used when running outside a bundle (e.g. `swift run`); mirrors Sources/serversHUD/Resources/machud.json.
    static let builtinManifest = HUDManifest(id: "xyz.machud.servershud", name: "serversHUD", socket: "servershud", panels: [
        HUDManifest.Panel(id: panelID, title: "Dev Servers", symbol: "server.rack",
                          defaultSize: HUDSize(PanelController.fullSize), compactSize: HUDSize(PanelController.compactSize),
                          verbs: verbs, settingsSchema: "settings.json", kind: .hover, order: 5),
        HUDManifest.Panel(id: widgetType, title: "Running Servers", symbol: "server.rack", kind: .widget,
                          widget: HUDWidgetSpec(sizes: [.small, .medium], defaultSize: .small, multiple: true, refresh: 5)),
    ])

    let manifest: HUDManifest
    let server: HUDSocketServer
    private(set) var router: HUDControlRouter!
    private let model: AppModel
    private let panel: PanelController
    private var lastPublished: String?

    init(model: AppModel, panel: PanelController) {
        self.model = model
        self.panel = panel
        manifest = HUDManifest.main ?? Self.builtinManifest
        server = HUDSocketServer(path: HUDSocket.path(for: AppEnvironment.socketName(default: manifest.socket)),
                                 label: "servershud.socket")
        router = HUDControlRouter(host: self, server: server, manifest: manifest)
    }

    func start() {
        router.install()
        if !server.start() { NSLog("serversHUD: control socket failed to start at %@", server.path) }
    }

    func stop() { server.stop() }

    /// Pushes `state` to subscribers when anything they can see changed (visibility, mode, the
    /// dev server count or their ports).
    func publishIfChanged() {
        let signature = panelStates.map { "\($0.visible)|\($0.mode)|\($0.badge ?? "")|\($0.status ?? "")" }.joined()
        guard signature != lastPublished else { return }
        lastPublished = signature
        router.publishState()
    }

    // MARK: - HUDPanelHost

    var panelDescriptors: [HUDManifest.Panel] { manifest.panels }

    var panelStates: [HUDPanelState] {
        [HUDPanelState(id: Self.panelID, visible: panel.isShown, mode: panel.mode, badge: model.badge, status: model.status)]
    }

    private func check(_ id: String) throws {
        guard id == Self.panelID else { throw HUDControlError.noSuchPanel(id) }
    }

    func showPanel(_ id: String) throws { try check(id); panel.show(takeFocus: false) }
    func togglePanel(_ id: String) throws { try check(id); panel.toggle(takeFocus: false) }
    func hidePanel(_ id: String) throws { try check(id); panel.hide() }

    /// MacHUD's dock: `from=`/`anchor=` slide out of the button to the assigned frame,
    /// `reason=hover` is a 0.08 s show that never takes key, `click`/`summon` make the panel key.
    func showPanel(_ id: String, options: [String: String]) throws {
        try check(id); panel.show(HUDPanelTransition(options))
    }

    /// `to=<edge>` slides back toward the dock in 0.1 s.
    func hidePanel(_ id: String, options: [String: String]) throws {
        try check(id); panel.hide(HUDPanelTransition(options))
    }

    func togglePanel(_ id: String, options: [String: String]) throws {
        try check(id); panel.toggle(HUDPanelTransition(options))
    }

    func setPanelFrame(_ id: String, frame: CGRect) throws {
        try check(id)
        guard frame.width >= 40, frame.height >= 40 else { throw HUDControlError.invalid("frame too small") }
        panel.setFrame(frame)
    }

    func setPanelMode(_ id: String, mode: HUDPanelMode) throws {
        try setPanelMode(id, mode: mode, options: HUDPanelModeOptions())
    }

    func setPanelMode(_ id: String, mode: HUDPanelMode, options: HUDPanelModeOptions) throws {
        try check(id)
        panel.setMode(mode, options: options)
    }

    // MARK: Settings

    func settings() -> [String: Any] { model.settings.json }

    func updateSettings(_ values: [String: String]) throws {
        do {
            try model.updateSettings(values)
        } catch let error as ServersSettings.SettingsError {
            throw HUDControlError.invalid(error.description)
        }
    }

    // MARK: Actions

    static func flag(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }

    /// `action list` / `servershud list`: the `devops --json servers` document, dev-only (with
    /// the ignore list) unless `all=1`.
    func listResponse(_ servers: [Server], all: Bool) -> [String: Any] {
        let rows = all ? servers : ServerFilter(devOnly: true, ignore: model.settings.ignoreList).apply(servers)
        var response = ServersDocument.make(rows)
        response["ok"] = true
        response["count"] = rows.count
        return response
    }

    func performAction(_ name: String, args: [String: String], done: @escaping ([String: Any]) -> Void) {
        switch name {
        case "show", "hide", "toggle":
            switch name {
            case "show": panel.show(takeFocus: false)
            case "hide": panel.hide()
            default: panel.toggle(takeFocus: false)
            }
            done(["ok": true, "visible": panel.isShown])
        case "refresh":
            model.refresh { [weak self] servers in
                guard let self else { return }
                done(["ok": true, "count": self.model.devServers.count, "total": servers.count])
            }
        case "list":
            let all = Self.flag(args["all"])
            model.refresh { [weak self] servers in
                guard let self else { return }
                done(self.listResponse(servers, all: all))
            }
        case "open":
            let port: Int?
            if let raw = args["port"] ?? args["_"] { port = Int(raw.trimmingCharacters(in: CharacterSet(charactersIn: ": "))) }
            else if let pid = args["pid"].flatMap(Int32.init) { port = model.servers.first { $0.pid == pid }?.ports.first }
            else { port = nil }
            guard let port, let url = ServerActions.url(port: port) else {
                done(["ok": false, "error": "port= required (1-65535), or pid= of a listed server"]); return
            }
            done(ServerActions.open(port: port) ? ["ok": true, "url": url.absoluteString]
                                                 : ["ok": false, "error": "could not open \(url.absoluteString)"])
        case "kill":
            guard let pid = (args["pid"] ?? args["_"]).flatMap(Int32.init) else {
                done(["ok": false, "error": "pid= required"]); return
            }
            // `force=1` on the socket is the caller's explicit confirmation of SIGKILL.
            let force = Self.flag(args["force"])
            // Kill against a fresh scan, so only a pid listening right now can be signalled.
            model.refresh { [weak self] servers in
                guard let self else { return }
                let outcome = ServerActions.kill(pid: pid, force: force, confirmed: force, servers: servers)
                guard outcome.ok else {
                    done(["ok": false, "pid": Int(pid), "error": outcome.description]); return
                }
                if !force { self.model.markStopping(pid) }
                Self.waitForExit(pid, timeout: 2) { exited in
                    self.model.refresh { _ in
                        done(["ok": true, "pid": Int(pid), "signal": outcome.signalName ?? "", "exited": exited])
                    }
                }
            }
        case "snapshot":
            // Not in the manifest: a PNG of the panel as it is now, for docs and checks.
            guard let path = args["path"], !path.isEmpty else { done(["ok": false, "error": "path= required"]); return }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            done(panel.writeSnapshot(to: url) ? ["ok": true, "path": url.path] : ["ok": false, "error": "snapshot failed"])
        default:
            done(["ok": false, "error": "unknown action \(name) (\(Self.actions.joined(separator: ", ")))"])
        }
    }

    /// Polls `kill(pid, 0)` off the main thread until the process is gone or `timeout` passes.
    static func waitForExit(_ pid: Int32, timeout: TimeInterval, completion: @escaping @MainActor (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = Date().addingTimeInterval(timeout)
            var alive = ServerActions.isAlive(pid)
            while alive && Date() < deadline {
                usleep(100_000)
                alive = ServerActions.isAlive(pid)
            }
            let exited = !alive
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(exited) } }
        }
    }

    func quit() { NSApp.terminate(nil) }
}
