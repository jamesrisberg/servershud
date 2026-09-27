import Foundation

/// User settings (schema: Sources/serversHUD/Resources/settings.json), stored as JSON at `<home>/settings.json`.
public struct ServersSettings: Codable, Equatable, Sendable {
    /// Seconds between rescans while the panel is visible.
    public var refreshInterval: Int = 2
    /// The panel's Dev only toggle starts on.
    public var devOnly: Bool = true
    /// Comma-separated process names hidden in dev-only mode.
    public var ignore: String = ""

    public init() {}

    public static let refreshRange: ClosedRange<Int> = 1...60

    /// Saved values are merged over the defaults key by key: a missing key, or one whose value no
    /// longer decodes, keeps its default and the other saved values are kept.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ServersSettings()
        refreshInterval = (try? c.decodeIfPresent(Int.self, forKey: .refreshInterval)) ?? d.refreshInterval
        refreshInterval = min(max(refreshInterval, Self.refreshRange.lowerBound), Self.refreshRange.upperBound)
        devOnly = (try? c.decodeIfPresent(Bool.self, forKey: .devOnly)) ?? d.devOnly
        ignore = (try? c.decodeIfPresent(String.self, forKey: .ignore)) ?? d.ignore
    }

    public var ignoreList: [String] { ServerFilter.ignoreList(ignore) }

    public var json: [String: Any] {
        ["refreshInterval": refreshInterval, "devOnly": devOnly, "ignore": ignore]
    }

    public enum SettingsError: Error, CustomStringConvertible, Equatable {
        case invalid(String)
        public var description: String { if case .invalid(let s) = self { return s }; return "" }
    }

    /// Applies string values (from `settings set`), validating all before changing any.
    public func applying(_ values: [String: String]) throws -> ServersSettings {
        var copy = self
        for (key, value) in values {
            switch key {
            case "refreshInterval":
                guard let n = Int(value), Self.refreshRange.contains(n) else {
                    throw SettingsError.invalid("refreshInterval must be a whole number of seconds between 1 and 60")
                }
                copy.refreshInterval = n
            case "devOnly":
                switch value.lowercased() {
                case "1", "true", "yes", "on": copy.devOnly = true
                case "0", "false", "no", "off": copy.devOnly = false
                default: throw SettingsError.invalid("devOnly must be true or false")
                }
            case "ignore":
                copy.ignore = ServerFilter.ignoreList(value).joined(separator: ", ")
            default:
                throw SettingsError.invalid("unknown setting \(key)")
            }
        }
        return copy
    }

    public static func load(from url: URL) -> ServersSettings {
        guard let data = try? Data(contentsOf: url) else { return ServersSettings() }
        return (try? JSONDecoder().decode(ServersSettings.self, from: data)) ?? ServersSettings()
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
