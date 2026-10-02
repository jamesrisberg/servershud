import AppKit
import HUDKit
import serversHUDKit
@testable import serversHUD
import XCTest

/// The `running` widget through HUDKit's `widget` verb (no windows are opened), plus the snapshot
/// path and the rescan pace.
@MainActor
final class WidgetHostTests: XCTestCase {
    private var dir: URL!
    private var model: AppModel!
    private var control: ControlHost!
    private var widgets: HUDWidgetHost!
    private var opened = 0

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("servershud-widget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        model = AppModel(settingsURL: dir.appendingPathComponent("preferences.json"))
        control = ControlHost(model: model, panel: PanelController(model: model))
        widgets = ServersWidgets.makeHost(manifest: ControlHost.builtinManifest, model: model) { [unowned self] in opened += 1 }
        widgets.presentsWindows = false
        control.router.widgetHost = widgets
    }

    override func tearDown() async throws {
        widgets = nil
        control = nil
        model = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func widget(_ args: [String: String]) -> [String: Any] {
        var response: [String: Any] = [:]
        control.router.handle("widget", args: args) { response = $0 }
        return response
    }

    func testHelloListsTheWidgetVerbAndPanel() {
        var hello: [String: Any] = [:]
        control.router.handle("hello", args: [:]) { hello = $0 }
        XCTAssertTrue((hello["verbs"] as? [String])?.contains("widget") == true, "\(hello)")
        let panels = hello["panels"] as? [[String: Any]] ?? []
        let running = panels.first { $0["id"] as? String == "running" }
        XCTAssertEqual(running?["kind"] as? String, "widget")
    }

    func testTypeIsRegisteredWithBothSizes() {
        XCTAssertEqual(widgets.types, ["running"])
        XCTAssertEqual(widgets.spec(for: "running")?.sizes, [.small, .medium])
    }

    func testInstanceLifecycle() {
        let created = widget(["action": "create", "instance": "a", "type": "running", "frame": "40,40,170,170"])
        XCTAssertEqual(created["ok"] as? Bool, true, "\(created)")
        XCTAssertEqual((created["instance"] as? [String: Any])?["size"] as? String, "small", "the manifest's default size")

        let updated = widget(["action": "update", "instance": "a", "size": "medium", "frame": "40,40,356,170"])
        XCTAssertEqual((updated["instance"] as? [String: Any])?["size"] as? String, "medium", "\(updated)")

        let tooBig = widget(["action": "update", "instance": "a", "size": "large"])
        XCTAssertEqual(tooBig["ok"] as? Bool, false)
        XCTAssertEqual(tooBig["error"] as? String, "running size must be one of small, medium")

        let list = widget(["action": "list"])
        XCTAssertEqual((list["instances"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(list["types"] as? [String], ["running"])

        XCTAssertEqual(widget(["action": "remove", "instance": "a"])["removed"] as? String, "a")
        XCTAssertEqual((widget(["action": "list"])["instances"] as? [[String: Any]])?.count, 0)
    }

    func testSeveralInstancesAreAllowed() {
        XCTAssertEqual(widget(["action": "create", "instance": "a", "type": "running", "frame": "40,40,170,170"])["ok"] as? Bool, true)
        XCTAssertEqual(widget(["action": "create", "instance": "b", "type": "running", "size": "medium", "frame": "240,40,356,170"])["ok"] as? Bool, true)
        XCTAssertEqual(widgets.instances.map(\.id), ["a", "b"])
    }

    func testSyncRestoresInstancesAfterARelaunch() {
        let instances = #"[{"instance":"a","type":"running","size":"medium","frame":[40,40,356,170],"layer":"float","settings":{}}]"#
        let reply = widget(["action": "sync", "instances": instances])
        XCTAssertEqual(reply["ok"] as? Bool, true, "\(reply)")
        XCTAssertEqual((reply["rejected"] as? [Any])?.count, 0)
        XCTAssertEqual(widgets.instance("a")?.size, .medium)
        XCTAssertEqual(widgets.instance("a")?.layer, .float)
    }

    func testTapOnTheWidgetOpensThePanel() throws {
        _ = widget(["action": "create", "instance": "a", "type": "running", "frame": "40,40,170,170"])
        try XCTUnwrap(widgets.context(for: "a")).openApp()
        XCTAssertEqual(opened, 1)
    }

    func testWidgetsAreNotDockPanels() {
        let manifest = ControlHost.builtinManifest
        XCTAssertEqual(manifest.dockPanels.map(\.id), ["servers"])
        XCTAssertEqual(manifest.widgetPanels.map(\.id), ["running"])
        // The hover panel verbs still refuse the widget type: it is not a panel.
        var response: [String: Any] = [:]
        control.router.handle("panel", args: ["id": "running", "show": "1"]) { response = $0 }
        XCTAssertEqual(response["ok"] as? Bool, false, "\(response)")
    }

    func testSnapshotsOfEverySizeWithSampleAndEmptyData() throws {
        let files = try ServersWidgets.writeSnapshots(host: widgets, model: model, to: dir.appendingPathComponent("shots"))
        XCTAssertEqual(files.map(\.lastPathComponent),
                       ["running-small.png", "running-medium.png", "running-small-empty.png", "running-medium-empty.png"])
        for file in files {
            let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
            XCTAssertGreaterThan(size, 1_000, file.lastPathComponent)
        }
        let (small, medium) = (try XCTUnwrap(NSImage(contentsOf: files[0])), try XCTUnwrap(NSImage(contentsOf: files[1])))
        XCTAssertEqual(small.size, NSSize(width: 170, height: 170))
        XCTAssertEqual(medium.size, NSSize(width: 356, height: 170))
    }

    func testFrozenModelKeepsTheSample() {
        model.freeze(with: ServersWidgets.sampleServers)
        var seen = 0
        model.refresh { seen = $0.count }
        XCTAssertEqual(seen, ServersWidgets.sampleServers.count, "a frozen model does not scan")
        XCTAssertEqual(model.devServers.count, ServersWidgets.sampleServers.count)
    }

    func testScanInterval() {
        let scan = AppDelegate.scanInterval
        XCTAssertEqual(scan(false, 2, 0), 15, "hidden panel, no widgets: the slow badge pace")
        XCTAssertEqual(scan(true, 2, 0), 2)
        XCTAssertEqual(scan(false, 2, 1), 5, "a widget on the desktop keeps the list fresher")
        XCTAssertEqual(scan(true, 2, 1), 2, "never slower than the panel's own pace")
        XCTAssertEqual(scan(true, 30, 2), 5)
    }
}
