import AppKit
import HUDKit
@testable import serversHUD
import XCTest

/// MacHUD's dock transitions (`panel show/hide from= to= anchor= reason=`) through HUDKit's
/// router against a real panel (the socket itself is not started).
@MainActor
final class ControlHostTests: XCTestCase {
    private var dir: URL!
    private var panel: PanelController!
    private var control: ControlHost!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("servershud-host-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel(settingsURL: dir.appendingPathComponent("preferences.json"))
        panel = PanelController(model: model)
        control = ControlHost(model: model, panel: panel)
    }

    override func tearDown() async throws {
        panel.panel.orderOut(nil)
        control = nil
        panel = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func send(_ args: [String: String]) -> [String: Any] {
        var response: [String: Any] = [:]
        control.router.handle("panel", args: ["id": "servers"].merging(args) { $1 }) { response = $0 }
        return response
    }

    /// Spins the main run loop until `condition` holds or `timeout` passes: the motions are
    /// run-loop animations, and the CI runner is slow to advance them.
    private func spin(until condition: @autoclosure () -> Bool, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testDockTransitionsThroughRouter() throws {
        // Inside the main screen's visible area, so AppKit does not push the window on-screen on a
        // small display (the CI runner's).
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let assigned = CGRect(x: (visible.minX + 40).rounded(), y: (visible.minY + 40).rounded(), width: 620, height: 420)
        XCTAssertEqual(send(["frame": "1", "x": "\(Int(assigned.minX))", "y": "\(Int(assigned.minY))", "w": "620", "h": "420"])["ok"] as? Bool, true)

        // Hover show: slides out of the bottom dock to the assigned frame, never takes key.
        let shown = send(["show": "1", "from": "bottom", "anchor": "100,0,44,44", "reason": "hover"])
        XCTAssertEqual(shown["visible"] as? Bool, true, "\(shown)")
        spin(until: panel.panel.frame == assigned)
        XCTAssertTrue(panel.panel.isVisible)
        XCTAssertFalse(panel.panel.isKeyWindow, "hover must not take key")
        XCTAssertEqual(panel.panel.frame, assigned)

        // Pointer leaves and comes straight back: the show wins over the hide in flight.
        XCTAssertEqual(send(["hide": "1", "to": "bottom"])["visible"] as? Bool, false)
        XCTAssertEqual(send(["show": "1", "from": "bottom", "anchor": "100,0,44,44", "reason": "hover"])["visible"] as? Bool, true)
        spin(until: panel.panel.frame == assigned && panel.panel.alphaValue == 1)
        XCTAssertTrue(panel.panel.isVisible, "the stale hide must not order the panel out")
        XCTAssertEqual(panel.panel.alphaValue, 1, accuracy: 0.01)
        XCTAssertEqual(panel.panel.frame, assigned)

        // A hide on its own slides out, orders out and restores the rest frame.
        XCTAssertEqual(send(["hide": "1", "to": "bottom"])["visible"] as? Bool, false)
        spin(until: !panel.panel.isVisible && panel.panel.frame == assigned)
        XCTAssertFalse(panel.panel.isVisible)
        XCTAssertEqual(panel.panel.frame, assigned)

        // Without an assigned frame the panel rests next to the anchor, above a bottom dock.
        panel.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))
        XCTAssertNil(panel.assignedFrame, "a user resize drops MacHUD's frame")
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let button = CGRect(x: screen.midX - 22, y: screen.minY, width: 44, height: 44)
        _ = send(["show": "1", "from": "bottom", "anchor": HUDPanelTransition.formatAnchor(button), "reason": "click"])
        spin(until: abs(panel.panel.frame.midX - button.midX) < 0.5 && panel.panel.frame.minY >= button.maxY)
        XCTAssertEqual(panel.panel.frame.size, assigned.size)
        XCTAssertEqual(panel.panel.frame.midX, button.midX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(panel.panel.frame.minY, button.maxY)

        XCTAssertEqual(send(["show": "1", "from": "middle"])["ok"] as? Bool, false)
    }

    func testPlainShowHideAndTimings() {
        XCTAssertEqual(send(["show": "1"])["visible"] as? Bool, true)
        spin(0.3)
        XCTAssertTrue(panel.panel.isVisible)
        XCTAssertFalse(panel.panel.isKeyWindow, "a plain socket show never takes key")
        XCTAssertEqual(send(["hide": "1"])["visible"] as? Bool, false)
        spin(0.3)
        XCTAssertFalse(panel.panel.isVisible)
        XCTAssertEqual(PanelController.hoverShowDuration, 0.08)
        XCTAssertEqual(PanelController.slideHideDuration, 0.1)
    }
}
