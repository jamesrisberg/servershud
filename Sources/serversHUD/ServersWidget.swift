import AppKit
import HUDKit
import serversHUDKit
import SwiftUI

/// The `running` desktop widget: how many dev servers are listening, and (medium) the first four.
/// It reads the same scan the panel does (dev-only, the ignore list applied), so it needs no
/// settings of its own. Small: the count, a status dot, the first ports; tapping it opens the
/// panel. Medium: port, project, framework and uptime per row; tapping a row opens
/// `http://localhost:<port>`, tapping the header opens the panel.
struct ServersWidgetView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var context: HUDWidgetContext

    private var widget: ServersWidgetModel { ServersWidgetModel(servers: model.devServers) }

    var body: some View {
        Group {
            switch context.size {
            case .small: small
            default: medium
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(context.size == .small ? 16 : 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    // MARK: Small

    private var small: some View {
        let widget = self.widget
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "server.rack").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                StatusDot(isRunning: widget.isRunning)
            }
            Spacer(minLength: 0)
            Text(String(widget.count))
                .font(.system(size: 52, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(widget.isRunning ? 1 : 0.45))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(widget.count == 1 ? "dev server" : "dev servers")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(widget.isRunning ? ports(widget) : "nothing listening")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.tail)
                .padding(.top, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { context.openApp() }
        .accessibilityLabel(widget.countText)
        .accessibilityAddTraits(.isButton)
    }

    private func ports(_ widget: ServersWidgetModel) -> String {
        let listed = widget.rows.prefix(3).map { ":\($0.port)" }.joined(separator: " ")
        return widget.count > 3 ? listed + " …" : listed
    }

    // MARK: Medium

    private var medium: some View {
        let widget = self.widget
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                StatusDot(isRunning: widget.isRunning)
                Text(widget.countText).font(.system(size: 13, weight: .semibold))
                Spacer()
                if widget.hiddenCount > 0 {
                    Text("+\(widget.hiddenCount) more").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Image(systemName: "server.rack").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { context.openApp() }
            if widget.rows.isEmpty {
                Spacer(minLength: 0)
                Text(widget.isRunning ? "Listening without a port to open" : "Start a server and it shows up here")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(widget.rows) { row in
                        ServerRow(row: row).onTapGesture { model.open(port: row.port) }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct StatusDot: View {
    var isRunning: Bool

    var body: some View {
        Circle()
            .fill(isRunning ? Color.green : Color.white.opacity(0.3))
            .frame(width: 8, height: 8)
            .shadow(color: isRunning ? Color.green.opacity(0.6) : .clear, radius: 3)
            .accessibilityHidden(true)
    }
}

private struct ServerRow: View {
    var row: ServersWidgetModel.Row

    var body: some View {
        HStack(spacing: 8) {
            Text(row.portText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .frame(width: 84, alignment: .leading)
                .lineLimit(1)
            Text(row.project)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(row.process) · \(row.uptime)")
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens localhost \(row.portText) in the browser")
        .accessibilityAddTraits(.isButton)
    }
}

/// The widget host: registers the `running` type and routes a tap on the widget's header to the panel.
@MainActor
enum ServersWidgets {
    static func makeHost(manifest: HUDManifest, model: AppModel, openPanel: @escaping () -> Void) -> HUDWidgetHost {
        let host = HUDWidgetHost(manifest: manifest)
        host.register(ControlHost.widgetType) { context in
            ServersWidgetView(model: model, context: context)
        }
        host.onOpen = { _ in openPanel() }
        return host
    }

    /// Sample servers for `--snapshot-widgets`: a plausible mix, deterministic.
    static var sampleServers: [Server] {
        func make(_ pid: Int32, _ ports: [Int], _ command: String, _ line: String, _ cwd: String, _ seconds: Int) -> Server {
            Server(pid: pid, uid: getuid(), ports: ports, command: command, commandLine: line, cwd: cwd,
                   etime: "", uptimeSeconds: seconds)
        }
        return [
            make(101, [3000], "node", "node /Users/me/shop/node_modules/.bin/next dev", "/Users/me/shop", 9_000),
            make(102, [5173, 24678], "node", "node /Users/me/blog/node_modules/.bin/vite", "/Users/me/blog", 2_700),
            make(103, [8000], "python3", "python3 manage.py runserver", "/Users/me/api-with-a-rather-long-name", 400),
            make(104, [8080], "go", "go run ./cmd/server", "/Users/me/gateway", 45),
            make(105, [9292], "ruby", "ruby bin/rails server", "/Users/me/legacy", 86_400 * 2),
        ]
    }

    /// Writes `running-<size>[-empty].png` for every declared size into `directory`.
    static func writeSnapshots(host: HUDWidgetHost, model: AppModel, to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for (suffix, servers) in [("", sampleServers), ("-empty", [])] as [(String, [Server])] {
            model.freeze(with: servers)
            for size in host.spec(for: ControlHost.widgetType)?.sizes ?? [] {
                let url = directory.appendingPathComponent("\(ControlHost.widgetType)-\(size.rawValue)\(suffix).png")
                try host.writeSnapshot(type: ControlHost.widgetType, size: size, to: url)
                written.append(url)
            }
        }
        return written
    }
}
