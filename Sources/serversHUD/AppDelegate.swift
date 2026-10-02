import AppKit
import HUDKit
import serversHUDKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var panel: PanelController!
    private var statusItem: NSStatusItem!
    private var control: ControlHost!
    /// The desktop widgets (`running`); kept for the app's lifetime.
    private var widgets: HUDWidgetHost!
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    static let toggleHotKey = HUDHotKey(key: "p", modifiers: ["control", "option"])
    /// While the panel is hidden or parked the badge is kept current at this slower pace.
    static let backgroundInterval: TimeInterval = 15
    /// While a desktop widget is placed the list is kept this fresh, panel or no panel.
    static let widgetInterval: TimeInterval = 5

    /// How often to rescan: `refreshInterval` while the panel is on screen, 15 s otherwise, and
    /// never slower than `widgetInterval` while a widget is on the desktop.
    static func scanInterval(panelLive: Bool, refreshInterval: Int, widgetCount: Int) -> TimeInterval {
        let base = panelLive ? TimeInterval(refreshInterval) : backgroundInterval
        return widgetCount > 0 ? min(base, widgetInterval) : base
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        HUDEditMenu.install(appName: "serversHUD")
        model = AppModel(settingsURL: AppEnvironment.settingsURL)
        panel = PanelController(model: model)
        control = ControlHost(model: model, panel: panel)
        // Before start(): MacHUD sends `widget sync` as soon as it connects.
        widgets = ServersWidgets.makeHost(manifest: control.manifest, model: model) { [weak self] in self?.panel.show(takeFocus: true) }
        control.router.widgetHost = widgets
        control.start()
        model.onScan = { [weak self] in self?.stateChanged() }
        panel.onStateChange = { [weak self] in self?.stateChanged() }
        setupStatusItem()
        // While MacHUD runs, its menu hosts this one and the icon hides (HUDKit menu bar consolidation).
        control.router.menuProvider = { [weak self] in self?.statusItem?.menu }
        // menuBar.consumed is kept in <home>/menubar.json, so SERVERSHUD_HOME isolates it too.
        HUDStatusItemPolicy.attach(statusItem, appID: control.manifest.id, store: .home(AppEnvironment.baseDirectory))
        if AppEnvironment.hotKeysEnabled {
            if HUDHotKeyCenter.shared.register(Self.toggleHotKey, onPress: { [weak self] in self?.panel.toggle(takeFocus: true) }) == nil {
                model.show("⌃⌥P is taken by another app; use the menu bar icon", error: true)
            }
        }
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        // `--snapshot-widgets <dir>`: write running-<size>.png (and -empty) from sample servers
        // and quit; no scan runs.
        if let directory = value("--snapshot-widgets") {
            do {
                let files = try ServersWidgets.writeSnapshots(host: widgets, model: model, to: URL(fileURLWithPath: directory))
                files.forEach { print($0.path) }
            } catch {
                NSLog("serversHUD: widget snapshot failed: %@", String(describing: error))
                fputs("snapshot failed: \(error)\n", stderr)
            }
            NSApp.terminate(nil)
            return
        }
        model.refresh()
        rescheduleTimer()
        // `--search <query>` and `--all` set up the list (used with --snapshot).
        if let query = value("--search") { model.searchText = query }
        if args.contains("--all") { model.devOnly = false }

        // `--snapshot <path.png>`: show the panel and write a PNG of it once the first scan has
        // landed (for docs and for checking the UI without Screen Recording permission).
        // `--snapshot-mode compact` pictures the tile.
        if let path = value("--snapshot") {
            if value("--snapshot-mode") == "compact" { panel.setMode(.compact) }
            panel.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                let ok = self.panel.writeSnapshot(to: URL(fileURLWithPath: path))
                NSLog("serversHUD: snapshot %@ %@", ok ? "written to" : "failed for", path)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        control.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show(takeFocus: true)
        return true
    }

    // MARK: - Refresh timer

    private func stateChanged() {
        rescheduleTimer()
        control.publishIfChanged()
        statusItem?.button?.title = model.devServers.isEmpty ? "" : " \(model.badge)"
    }

    private func rescheduleTimer() {
        let interval = Self.scanInterval(panelLive: panel.isLive, refreshInterval: model.settings.refreshInterval,
                                         widgetCount: widgets.instances.count)
        guard interval != timerInterval || timer == nil else { return }
        timer?.invalidate()
        timerInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh() }
        }
        timer?.tolerance = interval * 0.1
    }

    // MARK: - Status item

    private enum Tag: Int { case toggle = 1, compact, devOnly }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = HUDStatusIcon.image(fallbackSymbol: "server.rack", accessibilityDescription: "serversHUD")
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        let toggle = NSMenuItem(title: "Show Dev Servers", action: #selector(togglePanel), keyEquivalent: "p")
        toggle.keyEquivalentModifierMask = [.control, .option]
        toggle.tag = Tag.toggle.rawValue
        menu.addItem(toggle)
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: ""))
        menu.addItem(.separator())
        let devOnly = NSMenuItem(title: "Dev Servers Only", action: #selector(toggleDevOnly), keyEquivalent: "")
        devOnly.tag = Tag.devOnly.rawValue
        menu.addItem(devOnly)
        let compact = NSMenuItem(title: "Compact Tile", action: #selector(toggleCompact), keyEquivalent: "")
        compact.tag = Tag.compact.rawValue
        menu.addItem(compact)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit serversHUD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) && item.target == nil {
            item.target = self
        }
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            switch Tag(rawValue: item.tag) {
            case .toggle: item.title = panel.isShown ? "Hide Dev Servers" : "Show Dev Servers"
            case .compact: item.state = panel.mode == .compact ? .on : .off
            case .devOnly: item.state = model.devOnly ? .on : .off
            case nil: break
            }
        }
    }

    @objc private func togglePanel() { panel.toggle(takeFocus: true) }
    @objc private func refresh() { model.refresh() }
    @objc private func toggleDevOnly() { model.devOnly.toggle() }
    @objc private func toggleCompact() { panel.setMode(panel.mode == .compact ? .full : .compact) }
}
