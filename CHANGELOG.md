# Changelog

All notable changes to serversHUD are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/); the current version is in [VERSION](VERSION).

## [Unreleased]

## [0.1.0] - 2026-09-27

### Added
- serversHUDKit: the scan (`lsof -iTCP -sTCP:LISTEN`, one `ps` and one cwd `lsof` for all pids,
  off the main thread), grouped by process; the `system` flag (another user's process or an
  Apple daemon on a short deny list) and the Dev only filter; framework guess from the command
  line (Vite, Next.js, webpack, Rails, Django, Flask, Node, Python, Go); snapshot diff for
  new/stopped servers; kill/open/reveal/copy actions; JSON in the `devops --json servers` shape
  (`{collector, generatedAt, entries: [{name, path, status, details}]}`) with `framework` and
  `dev` added to `details`.
- Menu bar app (no Dock icon) with one hover panel `servers` on HUD glass: framework glyph, port
  chips that open `http://localhost:<port>`, cwd reveal in Finder, uptime, full command line,
  copy URL, Kill (SIGTERM) and two-click Force (SIGKILL), Dev only toggle, search (name, port,
  path, pid, framework), green glow for new servers and a footer naming stopped ones. A 44 pt
  compact tile with a dev server count badge. Rescans every `refreshInterval` s (default 2)
  while visible, every 15 s while hidden.
- Keys: Control-Option-P (global show/hide), Cmd-F, Cmd-R, Esc/Cmd-W.
- MacHUD contract through HUDKit: manifest `machud.json` (app `xyz.machud.servershud`, panel
  `servers`, dock `order` 5), settings schema, the HUDKit verb set, dock slide-out
  (`from=`/`to=`/`anchor=`/`reason=`; a hover show never takes key), `action refresh`, `list`,
  `kill`, `open`, `snapshot`; state events with the badge and first ports as status.
- Settings `refreshInterval`, `devOnly`, `ignore`, stored in `<home>/settings.json`; a saved
  value that does not decode falls back to its own default.
- Menu bar consolidation: while MacHUD runs, serversHUD's menu appears in MacHUD's status menu
  (`menu`, `menu-invoke`) and its own icon hides; `menuBar.consumed` (default `true`) is kept in
  `<home>/menubar.json`.
- App icon and template menu bar icon from the MacHUD family set, with the SF Symbol as fallback.
- `servershud` CLI: every socket verb plus `list`, `kill`, `open`, `watch`; `list`, `kill` and
  `open` scan directly when the app is not running.
- `--snapshot` (with `--snapshot-mode compact`, `--all`, `--search`) for PNG checks, and
  `SERVERSHUD_HOME` / `_SOCKET` / `_NO_HOTKEYS` for isolated test instances.
