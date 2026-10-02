# serversHUD

Every dev server listening on your Mac, in one floating glass panel. macOS 14+.

## What it is

serversHUD is a menu bar app (no Dock icon; the rack icon shows the dev server count) with one
**hover** panel on HUD glass. It lists the processes listening on TCP ports, grouped by process: a
framework glyph (Vite, Next.js, webpack, Rails, Django, Flask, Node, Python, Go, guessed from the
command line), the ports as chips you click to open `http://localhost:<port>`, the working
directory (click to reveal it in Finder), the uptime and the full command line. Kill sends
SIGTERM; Force sends SIGKILL after a second click. The link button copies the URL. Servers that
just started glow green for a few seconds; ones that just stopped are named in the footer.

It also serves a desktop widget, **Running Servers**: a small tile with the dev server count and a
status dot, or a medium tile listing the first four (port, project, framework and uptime; click a
row to open it in the browser). MacHUD places, moves and resizes widgets; see [Widgets](#widgets).

Inside MacHUD it is a hover button in the tool dock: the panel slides out while the pointer is
over it and hides when the pointer leaves. Compact mode is a 44 pt tile with a badge of the dev
server count. Dismissing hides the panel; summoning brings it back as it was. The list rescans
every 2 s while visible and every 15 s while hidden (to keep the badge current).

## Install

Check out HUDKit (the shared kit and build scripts) next to this repo, then install:

```sh
ls ~/dev            # hudkit  servershud
~/dev/servershud/install.sh
```

`install.sh` builds a release, quits a running copy, installs `/Applications/serversHUD.app`,
links the `servershud` command onto your PATH and launches it.

## Use

| Key | Does |
|---|---|
| Control-Option-P | show or hide the panel (global) |
| Cmd-F | search |
| Cmd-R | rescan now |
| Esc, Cmd-W | clear the search, then hide |

The menu bar icon does the same and has Quit. serversHUD takes no drops.

**Dev only** (on by default) hides system daemons, other users' processes and GUI apps that happen
to listen on ports (Zed, Docker Desktop, Control Center), plus any process names you list in the
`ignore` setting. The search field matches name, port (`:5173`), path, pid and framework.

### Without the app: `devops --json servers`

`servershud list`, `kill` and `open` work without the app running: the CLI scans directly with
serversHUDKit.

For scripts that do not want a Mac app at all, **`devops --json servers`** provides the same data:
the same three `lsof`/`ps` calls and the same JSON document
(`{collector, generatedAt, entries: [{name, path, status, details}]}`). serversHUD's `details` add
two fields devops does not have: `framework` and `dev`.

## Widgets

serversHUD serves one widget type, `running` ("Running Servers"), next to its hover panel. Add it
from MacHUD's widget gallery (needs MacHUD with contract 0.3), then:

| Size | Shows |
|---|---|
| small (1×1) | the dev server count, a green dot while any is listening, the first ports; click opens the panel |
| medium (2×1) | up to four rows: `:port`, project (the working directory's name), framework and uptime; click a row to open `http://localhost:<port>`, click the header to open the panel |

It counts what the panel's badge counts (Dev only, the `ignore` setting applied), so it has no
settings of its own, and several can be placed. While a widget is on the desktop serversHUD
rescans at least every 5 s, panel visible or not.

```sh
servershud widget create instance=a type=running size=medium frame=40,40,356,170
servershud widget list
servershud widget remove instance=a
```

## MacHUD contract

Panel `servers`, kind `hover`, dock `order` 5, socket `servershud`; widget type `running`
(`kind: widget`, sizes small and medium, no dock button). Verbs: the HUDKit set
(`hello`, `state`, `subscribe`, `panel show|hide|toggle|frame|mode`, `settings get|set|schema`,
`action`, `quit`, `widget`) plus `action refresh`, `list`, `kill`, `open`. Full reference:
[docs/CONTRACT.md](docs/CONTRACT.md).

```sh
servershud list                 # dev servers as JSON (same shape as `devops --json servers`)
servershud list all=1           # every listening process, system daemons included
servershud kill 4242            # SIGTERM; only a pid that is listening right now, and yours
servershud kill 4242 force=1    # SIGKILL
servershud open 5173            # http://localhost:5173 in your browser
servershud watch                # state events as they happen
```

## Settings

| Key | Type | Default | |
|---|---|---|---|
| `refreshInterval` | int | `2` | seconds between rescans while the panel is visible (1-60) |
| `devOnly` | bool | `true` | the Dev only toggle's starting state |
| `ignore` | string | `""` | comma-separated process names hidden in dev-only mode and left out of the badge |

Set them in MacHUD's settings window or with `servershud settings set key=value`. Stored in
`~/Library/Application Support/serversHUD/settings.json`.

## Build from source

Needs Swift 5.9+ and HUDKit checked out next to this repo (`../hudkit`).

```sh
swift test          # serversHUDKitTests + serversHUDTests
./build.sh          # build/serversHUD.app, CLI at Contents/Helpers/servershud (./build.sh debug for debug)
./install.sh        # build, install to /Applications, link the CLI, launch
build/serversHUD.app/Contents/MacOS/serversHUD --snapshot /tmp/servershud.png   # PNG of the panel
```

`--snapshot-widgets <dir>` writes `running-small.png`, `running-medium.png` and their `-empty`
variants from sample servers (no scan) and quits.

`--snapshot` writes the PNG 2 s after launch (once the first scan has landed) and keeps running; `--snapshot-mode compact` pictures the tile, `--all` turns
Dev only off, `--search <query>` filters. `build.sh` and `install.sh` call HUDKit's shared
`scripts/hud-build.sh` and `scripts/hud-install.sh` (set `HUDKIT_DIR` if HUDKit lives elsewhere).
The version comes from [VERSION](VERSION); changes are in [CHANGELOG.md](CHANGELOG.md).

Layout: `serversHUDKit` is the scan and everything testable (no UI); `serversHUD` is the app;
`serversHUDCLI` is the `servershud` tool.

## Isolation env vars for testing

| Variable | Effect |
|---|---|
| `SERVERSHUD_HOME` | base directory for everything serversHUD writes (default `~/Library/Application Support/serversHUD`); also keeps panel frames apart from the real instance |
| `SERVERSHUD_SOCKET` | socket name (default `servershud`); the CLI honours it too |
| `SERVERSHUD_NO_HOTKEYS` | set to skip registering global hotkeys |

```sh
SERVERSHUD_HOME=$(mktemp -d) SERVERSHUD_SOCKET=servershud-test SERVERSHUD_NO_HOTKEYS=1 \
  build/serversHUD.app/Contents/MacOS/serversHUD &
SERVERSHUD_SOCKET=servershud-test build/serversHUD.app/Contents/Helpers/servershud hello
```

## License

MIT, see [LICENSE](LICENSE).
