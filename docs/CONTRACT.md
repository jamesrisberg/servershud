# serversHUD's MacHUD contract

serversHUD implements the MacHUD contract through HUDKit; the canonical spec is HUDKit's
[docs/CONTRACT.md](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md). MacHUD reads
`serversHUD.app/Contents/Resources/machud.json` without launching the app and talks to the running
app over a Unix socket.

The shared parts are specified there and not repeated here: [socket](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#socket) (location,
framing, replies), the [required verbs](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#verbs), [`subscribe`](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#subscribe-and-state-events),
the [settings schema](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#settings-schema) format, [hover and windowed behaviour](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#behaviour-hover-and-windowed),
the [launch announcement](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#launch-announcement) and [menu bar consolidation](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#menu-bar-consolidation).
This page lists what serversHUD adds.

- Manifest: `Sources/serversHUD/Resources/machud.json`: app `xyz.machud.servershud`, socket `servershud`, a hover panel
  `servers` (`kind: hover`, symbol `server.rack`, default 620x420, compact 44x44, settings schema
  `settings.json`, verbs `show hide toggle frame mode refresh kill open list`, dock `order` 5:
  after Scratch, Stash, ffmpegHUD and magickHUD).
- Widget: a second manifest panel `running` (`kind: widget`, title "Running Servers", sizes
  `small` and `medium`, default `small`, `multiple` true, `refresh` 5, no per-instance settings
  schema). It is not a dock panel (HUDKit's `dockPanels` leaves it out) and takes no `panel`
  verbs. `HUDWidgetHost` serves the `widget` verb (see [Widgets](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#widgets)); the host is set on the router before the socket starts, so MacHUD's `widget sync` after a connect restores the instances. A tap on the small widget or on the medium header opens the panel (`onOpen`), a tap on a medium row opens `http://localhost:<port>`. The widget reads the same scan as the panel (dev-only, the ignore list applied); while any instance exists serversHUD rescans at least every 5 s.
- Hover: MacHUD shows the panel while the pointer is over its dock button and hides it on leave.
  `panel show`/`hide`/`toggle` fade in 0.22 s / out 0.18 s and keep the last frame and mode; a
  socket show never activates serversHUD, and only `reason=click`/`summon` makes the panel key
  (as does clicking it, for the search field). Dock options: `from=<edge>` slides out of that
  edge to the `panel frame` MacHUD assigned (else next to `anchor=x,y,w,h`), in 0.08 s with
  `reason=hover`; `hide to=<edge>` slides back in 0.1 s. A show during a hide wins. Dismiss (the header's close button, Esc, Cmd-W) hides; it never quits.
- Scanning: `lsof -nP -iTCP -sTCP:LISTEN -Fpcn`, then one `ps -o pid=,uid=,etime=,command=` and
  one `lsof -a -p <pids> -d cwd -Fpn` for all pids, off the main thread. Every `refreshInterval`
  seconds (default 2) while the panel is shown and not parked, every 15 s otherwise.
- Socket: `~/Library/Application Support/MacHUD/sockets/servershud.sock` (0600), one JSON object
  per line: `{"command": "...", "args": {...}}` in, `{"ok": true, ...}` or
  `{"ok": false, "error": "..."}` out.
- CLI: `servershud <command> [key=value ...]` (in `serversHUD.app/Contents/Helpers/servershud`,
  linked onto PATH by `install.sh`). `list`, `kill`, `open` and `refresh` are shorthands for
  `action name=<verb>`; `list`, `kill` and `open` fall back to scanning directly when the app is
  not running.

## Verbs

| Command | Args | Result |
|---|---|---|
| `hello` | | `{app, name, hudkit, version, panels, verbs}`: `hudkit` is the contract version, `version` the app's (`VERSION`) |
| `state` | | `{panels: [{id: "servers", visible, mode, badge, status}]}`: `badge` is the dev server count (dev-only, ignore list applied, no search), `status` their first ports (`:3000 :5173 …`, or `no dev servers`) |
| `subscribe` | `events=state` (optional) | acknowledged, then `{"event": "state", "panels": [...]}` whenever visibility, mode, the badge or the status changes (checked after every scan). `servershud watch` prints them. |
| `panel show` / `hide` / `toggle` | `id=servers`, optional `from=`/`to=<edge>`, `anchor=x,y,w,h`, `reason=hover\|click\|summon` | fades in or out at the last frame and mode, without taking focus; `from=`/`to=` slide out of / back into the dock (see Hover above) |
| `panel frame` | `id=servers x= y= w= h=` | AppKit screen coordinates; kept as the frame for the current mode |
| `panel mode` | `id=servers` + `full`, `compact` or `parked` | `compact` is the 44 pt tile with the count badge (a click opens the full panel); `parked` slides to the nearest screen edge leaving a 14 pt sliver, or to `edge=` with a `peek=` pt sliver when given (remembered) |
| `settings get` | `key=` (optional) | see below |
| `settings set` | `key=value ...` | validates every value before applying any |
| `action refresh` | | rescans now; `{count, total}` (dev servers, every listener) |
| `action list` | `all=1` (optional) | a fresh scan as the `devops --json servers` document plus `ok` and `count`: `{ok, count, collector: "servers", generatedAt, entries: [...]}`. Dev servers only unless `all=1` |
| `action kill` | `pid=`, `force=1` (optional) | rescans, then sends SIGTERM (or SIGKILL with `force=1`, which is the caller's confirmation) — only to a pid that is listening right now and belongs to the current user; never pid 0/1 or serversHUD itself. Waits up to 2 s for the process to exit and rescans: `{pid, signal, exited}`. Refusals: `{ok: false, error: "not a listening server" / "pid N belongs to another user" / ...}` |
| `action open` | `port=` (or `pid=` of a listed server) | opens `http://localhost:<port>`: `{url}` |
| `action show` / `hide` / `toggle` | | same as the panel verbs |
| `action snapshot` | `path=` | writes a PNG of the panel as it is (not in the manifest; for docs and checks) |
| `widget` | `action=create\|update\|remove\|list\|sync\|edit\|reveal\|schema` | HUDKit's widget verb for type `running` (sizes `small`, `medium`); `schema` answers `unsupported` (no per-instance settings). `servershud widget list`, `widget create instance=a type=running frame=40,40,170,170` |
| `quit` | | replies, then quits (the socket file is removed) |
| `help` | | lists the registered commands |

### Entries

Each `entries[]` element has the `devops --json servers` shape, `{name, path, status, details}`:

```json
{"name": "python3.12 :8765", "path": "/tmp/site", "status": "healthy",
 "details": {"pid": 94578, "ports": [8765], "command": "python3.12",
             "commandLine": "python3 -m http.server 8765", "cwd": "/tmp/site",
             "uptime": "41s", "uptimeSeconds": 41, "etime": "00:41", "uid": 501,
             "system": false, "framework": "python", "dev": true}}
```

`command` is lsof's short name, `commandLine` the full command collapsed to one line and capped at
200 characters. `cwd`, `uptime`, `uptimeSeconds`, `etime` and `uid` are `null` when `ps`/`lsof` did
not report them. `system` means another user's process (or no `ps` row) or an Apple daemon on
the deny list. serversHUD adds `framework` (`vite`, `next`, `webpack`, `rails`,
`django`, `flask`, `node`, `python`, `go` or `null`) and `dev` (what Dev only keeps: not `system`,
and either a known framework or not a GUI app / OS binary). Entries are sorted by first port.

## Settings

`Sources/serversHUD/Resources/settings.json` describes them for MacHUD's shared settings window. Values are stored in
`<home>/settings.json`, where home is `~/Library/Application Support/serversHUD` or `$SERVERSHUD_HOME`.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `refreshInterval` | int (1-60) | `2` | seconds between rescans while the panel is visible |
| `devOnly` | bool | `true` | the Dev only toggle's starting state (setting it also flips the toggle) |
| `ignore` | string | `""` | comma-separated process names (lsof's `command`, case-insensitive) hidden in dev-only mode, `action list` without `all=1`, and the badge |

## Menu bar consolidation

While MacHUD runs it shows serversHUD's status menu inside its own (`menu`, `menu-invoke`) and
the menu bar icon hides; it comes back when MacHUD quits or the user turns the
`menuBar.consumed` setting off (served by HUDKit's router, default `true`). The setting is
kept in `<home>/menubar.json` (so `SERVERSHUD_HOME` isolates it), never in the user's real preferences from a test instance.
See [menu bar consolidation](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#menu-bar-consolidation).

## Environment

| Variable | Read by | Effect |
|---|---|---|
| `SERVERSHUD_HOME` | app, CLI | base directory for settings; an isolated instance also keeps its panel frames apart from the real one |
| `SERVERSHUD_SOCKET` | app, CLI | socket name instead of `servershud` |
| `SERVERSHUD_NO_HOTKEYS` | app | skip global hotkeys |

A second instance runs beside the real one, e.g. for tests:

```sh
SERVERSHUD_HOME=/tmp/sh-test SERVERSHUD_SOCKET=servershud-test SERVERSHUD_NO_HOTKEYS=1 \
  build/serversHUD.app/Contents/MacOS/serversHUD &
SERVERSHUD_SOCKET=servershud-test build/serversHUD.app/Contents/Helpers/servershud state
```

## Launch flags

| Flag | Effect |
|---|---|
| `--snapshot <path.png>` | show the panel and write a PNG of it 2 s later, once the first scan has landed (logged; the app keeps running); serves no control socket, announces nothing, registers no hotkey and adds no menu bar item, so it never touches a running instance |
| `--snapshot-mode compact` | with `--snapshot`: picture the 44 pt tile |
| `--all` | start with Dev only off |
| `--search <query>` | start with the search field filled |
