import Foundation

/// A best guess at what kind of server a process is, from its name and command line. Used for
/// the glyph beside a row and to keep dev servers visible in dev-only mode even when they run
/// out of an app bundle's toolchain.
public enum Framework: String, CaseIterable, Codable, Sendable {
    case vite, next, webpack, rails, django, flask, node, python, go

    /// Short label drawn in the glyph.
    public var label: String {
        switch self {
        case .vite: return "Vi"
        case .next: return "N"
        case .webpack: return "Wp"
        case .rails: return "Rb"
        case .django: return "Dj"
        case .flask: return "Fl"
        case .node: return "JS"
        case .python: return "Py"
        case .go: return "Go"
        }
    }

    public var title: String {
        switch self {
        case .vite: return "Vite"
        case .next: return "Next.js"
        case .webpack: return "webpack"
        case .rails: return "Rails"
        case .django: return "Django"
        case .flask: return "Flask"
        case .node: return "Node"
        case .python: return "Python"
        case .go: return "Go"
        }
    }

    /// Specific frameworks first, then the runtime they sit on.
    public static func detect(command: String, commandLine: String) -> Framework? {
        let line = commandLine.lowercased()
        let tokens = Self.tokens(line)
        let names = Set(tokens.map { ($0 as NSString).lastPathComponent })
        func has(_ word: String) -> Bool { names.contains(word) || tokens.contains { $0.contains("/\(word)/") } }

        if line.hasPrefix("next-server") || has("next") || line.contains("/next/dist/") { return .next }
        if has("vite") || line.contains("/vite/bin/") { return .vite }
        if has("webpack") || has("webpack-dev-server") || line.contains("/webpack/bin/") { return .webpack }
        if has("rails") || names.contains("puma") || line.contains("puma ") || line.hasPrefix("puma") { return .rails }
        if (names.contains("manage.py") && names.contains("runserver")) || has("django") { return .django }
        if has("flask") || line.contains("-m flask") { return .flask }

        let exe = (tokens.first.map { ($0 as NSString).lastPathComponent } ?? "")
        let name = command.lowercased()
        let runtimes = [exe, name]
        if runtimes.contains(where: { $0 == "node" || $0 == "bun" || $0 == "deno" || $0.hasPrefix("node") }) { return .node }
        if runtimes.contains(where: { $0.hasPrefix("python") || $0 == "uvicorn" || $0 == "gunicorn" || $0 == "hypercorn" }) {
            return .python
        }
        if line.contains("/go-build") || tokens.prefix(2) == ["go", "run"] || name == "go" { return .go }
        return nil
    }

    static func tokens(_ line: String) -> [String] {
        line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }
}
