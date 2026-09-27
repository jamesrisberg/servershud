import Foundation

/// Isolation switches for tests and parallel instances:
///
/// - `SERVERSHUD_HOME`: base directory (settings in `<home>/settings.json`); default
///   `~/Library/Application Support/serversHUD`. An isolated instance also keeps its panel
///   frames apart from the real one's.
/// - `SERVERSHUD_SOCKET`: socket name under MacHUD's sockets directory; default `servershud`.
/// - `SERVERSHUD_NO_HOTKEYS`: set to skip registering the global hotkey.
enum AppEnvironment {
    static let environment = ProcessInfo.processInfo.environment

    static var isolatedHome: String? {
        environment["SERVERSHUD_HOME"].flatMap { $0.isEmpty ? nil : $0 }
    }

    static var baseDirectory: URL {
        if let home = isolatedHome {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("serversHUD", isDirectory: true)
    }

    static var settingsURL: URL { baseDirectory.appendingPathComponent("settings.json") }

    /// Where panel frames are remembered: the app's defaults, or a separate suite when
    /// `SERVERSHUD_HOME` isolates this instance (so a test run never moves the real panel).
    static let defaults: UserDefaults = isolatedHome == nil
        ? .standard
        : UserDefaults(suiteName: "xyz.machud.servershud.isolated") ?? .standard

    static func socketName(default name: String) -> String {
        environment["SERVERSHUD_SOCKET"].flatMap { $0.isEmpty ? nil : $0 } ?? name
    }

    static var hotKeysEnabled: Bool { environment["SERVERSHUD_NO_HOTKEYS"] == nil }
}
