import Foundation
import HUDKit
import XCTest
@testable import serversHUD

/// The shipped machud.json, settings.json and Info.plist are what MacHUD reads without launching
/// serversHUD; keep them valid and in step with the code.
final class ManifestTests: XCTestCase {
    private var resources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/serversHUD/Resources")
    }

    func testManifestDecodes() throws {
        let manifest = try HUDManifest.decode(Data(contentsOf: resources.appendingPathComponent(HUDManifest.fileName)))
        XCTAssertEqual(manifest.id, "xyz.machud.servershud")
        XCTAssertEqual(manifest.name, "serversHUD")
        XCTAssertEqual(manifest.socket, "servershud")
        let panel = try XCTUnwrap(manifest.panel(id: "servers"))
        XCTAssertEqual(panel.kind, .hover, "MacHUD drops the list down on hover and hides it on leave")
        XCTAssertEqual(panel.order, 5, "MacHUD's dock: Scratch 1, Stash 2, ffmpegHUD 3, magickHUD 4, then serversHUD")
        XCTAssertEqual(panel.symbol, "server.rack")
        XCTAssertEqual(panel.compactSize, HUDSize(width: 44, height: 44))
        for verb in ["show", "hide", "toggle", "refresh", "kill", "open", "list"] {
            XCTAssertTrue(panel.verbs.contains(verb), verb)
        }
        let schemaName = try XCTUnwrap(panel.settingsSchema)
        let schema = try HUDSettingsSchema.decode(Data(contentsOf: resources.appendingPathComponent(schemaName)))
        XCTAssertEqual(Set(schema.settings.map(\.key)), ["refreshInterval", "devOnly", "ignore"])
        XCTAssertEqual(schema.field("refreshInterval")?.type, .int)
        XCTAssertEqual(schema.field("devOnly")?.type, .bool)
        XCTAssertEqual(schema.field("ignore")?.type, .string)
    }

    func testWidgetPanel() throws {
        let manifest = try HUDManifest.decode(Data(contentsOf: resources.appendingPathComponent(HUDManifest.fileName)))
        let widget = try XCTUnwrap(manifest.panel(id: "running"))
        XCTAssertEqual(widget.kind, .widget)
        XCTAssertEqual(widget.symbol, "server.rack")
        let spec = try XCTUnwrap(widget.widget)
        XCTAssertEqual(spec.sizes, [.small, .medium])
        XCTAssertEqual(spec.defaultSize, .small)
        XCTAssertNil(spec.settingsSchema, "no per-instance settings: the app-wide ignore list applies")
        XCTAssertEqual(manifest.widgetPanels.map(\.id), ["running"])
        XCTAssertEqual(manifest.dockPanels.map(\.id), ["servers"], "the widget never becomes a dock button")
        XCTAssertEqual(manifest.panels.count, 2)
    }

    @MainActor
    func testBuiltinManifestMirrorsTheFile() throws {
        let file = try HUDManifest.decode(Data(contentsOf: resources.appendingPathComponent(HUDManifest.fileName)))
        XCTAssertEqual(ControlHost.builtinManifest, file)
    }

    func testInfoPlist() throws {
        let data = try Data(contentsOf: resources.appendingPathComponent("Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "xyz.machud.servershud")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "serversHUD")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertNotNil(plist["NSHumanReadableCopyright"])
    }
}
