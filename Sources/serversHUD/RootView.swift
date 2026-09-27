import serversHUDKit
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    var expand: () -> Void = {}
    var dismiss: () -> Void = {}

    var body: some View {
        Group {
            if model.isCompact {
                CompactTile(model: model, expand: expand)
            } else {
                VStack(spacing: 0) {
                    HeaderView(model: model, dismiss: dismiss)
                    Divider().opacity(0.4)
                    ServerList(model: model)
                    FooterView(model: model)
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Compact

/// The 44 pt tile: a rack glyph with the dev server count. A click opens the full panel.
struct CompactTile: View {
    @ObservedObject var model: AppModel
    var expand: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "server.rack")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(model.devServers.isEmpty ? 0.45 : 0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !model.devServers.isEmpty {
                Text(model.badge)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(Color.green.opacity(0.85)))
                    .padding(3)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .onTapGesture(perform: expand)
        .help("\(model.badge) dev server\(model.devServers.count == 1 ? "" : "s"): \(model.status)")
    }
}

// MARK: - Header

struct HeaderView: View {
    @ObservedObject var model: AppModel
    var dismiss: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack").foregroundStyle(.secondary)
            Text("Dev Servers").font(.system(size: 13, weight: .semibold))
            Text("\(model.visible.count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
                TextField("Search name, port, path", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                if !model.searchText.isEmpty {
                    Button { model.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .frame(width: 190)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
            Toggle("Dev only", isOn: $model.devOnly)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11))
                .help("Hide system daemons, other users' processes and GUI apps")
            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(model.scanning ? 180 : 0))
                    .animation(.easeInOut(duration: 0.3), value: model.scanning)
            }
            .buttonStyle(.plain)
            .help("Refresh (⌘R)")
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Hide (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .onChange(of: model.focusSearchToken) { _, _ in searchFocused = true }
    }
}

// MARK: - List

struct ServerList: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let rows = model.visible
        if rows.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "powersleep").font(.system(size: 22)).foregroundStyle(.tertiary)
                Text(emptyText).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(rows) { server in
                        ServerRowView(model: model, server: server, isNew: model.isNew(server),
                                      killState: model.killState[server.pid])
                    }
                }
                .padding(10)
            }
        }
    }

    private var emptyText: String {
        if model.lastScan == nil { return "Scanning…" }
        if !model.searchText.isEmpty { return "No servers match “\(model.searchText)”" }
        return model.devOnly ? "No dev servers listening" : "Nothing is listening on TCP"
    }
}

struct ServerRowView: View {
    @ObservedObject var model: AppModel
    let server: Server
    let isNew: Bool
    let killState: AppModel.KillState?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            FrameworkGlyph(framework: server.framework, system: server.system)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(server.command).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let f = server.framework {
                        Text(f.title).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Text("pid \(String(server.pid))").font(.system(size: 10).monospacedDigit()).foregroundStyle(.tertiary)
                    if isNew {
                        Text("NEW").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
                    }
                    Spacer(minLength: 4)
                    Label(server.uptime, systemImage: "clock")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help(server.etime.isEmpty ? "uptime unknown" : "up \(server.etime)")
                }
                HStack(spacing: 4) {
                    ForEach(server.ports, id: \.self) { port in
                        PortChip(port: port) { model.open(port: port) }
                            .contextMenu {
                                Button("Open http://localhost:\(port)") { model.open(port: port) }
                                Button("Copy URL") { model.copyURL(server, port: port) }
                            }
                    }
                    if let cwd = server.cwd {
                        Button { model.reveal(server) } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "folder").font(.system(size: 9))
                                Text(Self.abbreviate(cwd)).lineLimit(1).truncationMode(.middle)
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal \(cwd) in Finder")
                    }
                }
                Text(server.commandLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(server.commandLine)
            }
            actions
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isNew ? Color.green.opacity(0.14) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isNew ? Color.green.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.4), value: isNew)
    }

    private var actions: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Button { model.copyURL(server) } label: { Image(systemName: "link") }
                    .help("Copy http://localhost:\(server.ports.first.map(String.init) ?? "")")
                    .disabled(server.ports.isEmpty)
                if killState == .stopping {
                    Text("Stopping…").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Button("Kill") { model.kill(server) }
                        .help("Send SIGTERM to \(server.pid)")
                }
            }
            Button(killState == .forceArmed ? "Confirm Force" : "Force") { model.forceKill(server) }
                .foregroundStyle(killState == .forceArmed ? Color.red : Color.secondary)
                .help(killState == .forceArmed ? "Click again to send SIGKILL" : "SIGKILL (asks for a second click)")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.system(size: 11))
        .disabled(server.system)
    }

    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

struct PortChip: View {
    let port: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(":\(String(port))")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(hover ? Color.white : Color.accentColor)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(hover ? 0.55 : 0.18)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Open http://localhost:\(String(port))")
    }
}

/// A two-letter badge for the framework guess (or a plain rack for unknown servers).
struct FrameworkGlyph: View {
    let framework: Framework?
    let system: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(0.85))
            if let framework {
                Text(framework.label).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            } else {
                Image(systemName: system ? "gearshape" : "server.rack")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: 28, height: 28)
        .help(framework?.title ?? (system ? "System process" : "Unknown server"))
    }

    var color: Color {
        switch framework {
        case .vite: return Color(red: 0.55, green: 0.36, blue: 0.96)
        case .next: return Color(white: 0.32)
        case .webpack: return Color(red: 0.17, green: 0.55, blue: 0.85)
        case .rails: return Color(red: 0.8, green: 0.1, blue: 0.1)
        case .django: return Color(red: 0.05, green: 0.36, blue: 0.24)
        case .flask: return Color(red: 0.35, green: 0.35, blue: 0.4)
        case .node: return Color(red: 0.3, green: 0.6, blue: 0.25)
        case .python: return Color(red: 0.2, green: 0.4, blue: 0.65)
        case .go: return Color(red: 0.0, green: 0.62, blue: 0.75)
        case nil: return Color.white.opacity(0.15)
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            if let message = model.message {
                Image(systemName: message.error ? "exclamationmark.triangle" : "info.circle")
                    .foregroundStyle(message.error ? Color.orange : Color.secondary)
                Text(message.text).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(message.error ? Color.orange : Color.secondary)
                Spacer(minLength: 0)
            } else {
                if model.devOnly, model.hiddenCount > 0 {
                    Text("\(model.hiddenCount) system/app listener\(model.hiddenCount == 1 ? "" : "s") hidden")
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("every \(model.settings.refreshInterval)s").foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 10))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 24)
    }
}
