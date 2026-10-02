import Foundation
import HUDKit
import serversHUDKit

// `servershud <command> [key=value ...]`: talks to serversHUD's MacHUD control socket. `list`,
// `kill` and `open` also work without the app running: they scan directly with serversHUDKit.
//
//   servershud list                 # dev servers, as `devops --json servers` prints them
//   servershud list all=1           # every listening process
//   servershud kill 4242            # SIGTERM (pid= works too)
//   servershud kill 4242 force=1    # SIGKILL
//   servershud open 5173            # http://localhost:5173 (port= works too)
//   servershud panel show id=servers
//   servershud watch

let usage = """
usage: servershud <command> [key=value ...]
  list [all=1] [compact=1]          dev servers (all=1: every listener) as devops-style JSON
  kill <pid> | pid= [force=1]       SIGTERM a listening server; force=1 sends SIGKILL
  open <port> | port=               open http://localhost:<port>
  refresh                           rescan now (app only)
  hello | state | help | quit
  panel show|hide|toggle id=servers
  panel frame id=servers x= y= w= h=
  panel mode id=servers full|compact|parked
  widget list | create instance= type=running [size= frame=x,y,w,h layer=]
  widget update|remove instance= ... | edit on|off | reveal on|off | schema type=running
  action <verb> [k=v ...]           the long form of list/kill/open/refresh
  settings get [key=]  |  settings set key=value ...
  watch [events=state]              stream events (Ctrl-C to stop)

list, kill and open scan directly when serversHUD is not running.
Environment: SERVERSHUD_SOCKET picks the socket name (default servershud).

"""

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "ctl" { arguments.removeFirst() }
guard let command = arguments.first, !["-h", "--help"].contains(command) else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(arguments.isEmpty ? 2 : 0)
}

let socketName = ProcessInfo.processInfo.environment["SERVERSHUD_SOCKET"].flatMap { $0.isEmpty ? nil : $0 } ?? "servershud"
let path = HUDSocket.path(for: socketName)

func fail(_ message: String, status: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("servershud: \(message)\n".utf8))
    exit(status)
}

func flag(_ value: String?) -> Bool { ["1", "true", "yes", "on"].contains(value?.lowercased() ?? "") }

func printJSON(_ object: Any, pretty: Bool = true) {
    var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
    if pretty { options.insert(.prettyPrinted) }
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: options) else { fail("cannot encode JSON") }
    print(String(decoding: data, as: UTF8.self))
}

/// Sends one request; nil when the app is not running.
func request(_ verb: String, _ args: [String: String]) -> [String: Any]? {
    do {
        return try HUDSocketClient(path: path, timeout: 30).request("action", args: args.merging(["name": verb]) { a, _ in a })
    } catch HUDSocketError.notRunning, HUDSocketError.pathTooLong {
        return nil
    } catch {
        fail("\(error)")
    }
}

let shorthands: Set<String> = ["list", "kill", "open", "refresh"]
if shorthands.contains(command) {
    var args = HUDSocketClient.parseArguments(Array(arguments.dropFirst()))
    // `kill 4242` / `open 5173`: the bare word is the pid or port.
    if let bare = args.removeValue(forKey: "_"), command == "kill" || command == "open", Int(bare) != nil {
        args.removeValue(forKey: bare)
        args[command == "kill" ? "pid" : "port"] = args[command == "kill" ? "pid" : "port"] ?? bare
    }
    let pretty = !flag(args.removeValue(forKey: "compact"))

    if var response = request(command, args) {
        if command == "list", response["ok"] as? Bool == true {
            // The document devops prints: {collector, generatedAt, entries}.
            response["ok"] = nil
            response["count"] = nil
        }
        printJSON(response, pretty: pretty)
        exit(response["ok"] as? Bool == false ? 1 : 0)
    }

    // serversHUD is not running: do it here.
    let home = ProcessInfo.processInfo.environment["SERVERSHUD_HOME"].flatMap { $0.isEmpty ? nil : ($0 as NSString).expandingTildeInPath }
        ?? NSHomeDirectory() + "/Library/Application Support/serversHUD"
    let settings = ServersSettings.load(from: URL(fileURLWithPath: home).appendingPathComponent("settings.json"))
    switch command {
    case "list":
        let servers = ServerScanner().scan()
        let rows = flag(args["all"]) ? servers : ServerFilter(devOnly: true, ignore: settings.ignoreList).apply(servers)
        FileHandle.standardOutput.write(ServersDocument.data(rows, pretty: pretty))
        print("")
    case "kill":
        guard let pid = args["pid"].flatMap(Int32.init) else { fail("kill needs a pid: servershud kill <pid> [force=1]", status: 2) }
        let force = flag(args["force"])
        let outcome = ServerActions.kill(pid: pid, force: force, confirmed: force, servers: ServerScanner().scan())
        guard outcome.ok else { printJSON(["ok": false, "pid": Int(pid), "error": outcome.description]); exit(1) }
        var alive = true
        for _ in 0..<20 where alive { usleep(100_000); alive = ServerActions.isAlive(pid) }
        printJSON(["ok": true, "pid": Int(pid), "signal": outcome.signalName ?? "", "exited": !alive])
    case "open":
        guard let port = args["port"].flatMap({ Int($0.trimmingCharacters(in: CharacterSet(charactersIn: ": "))) }),
              let url = ServerActions.url(port: port) else { fail("open needs a port: servershud open <port>", status: 2) }
        guard ServerActions.open(port: port) else { fail("could not open \(url.absoluteString)") }
        printJSON(["ok": true, "url": url.absoluteString])
    default:
        fail("serversHUD is not running (no socket at \(path))")
    }
    exit(0)
} else if command == "settings", arguments.count > 1, ["get", "set"].contains(arguments[1]) {
    // Send the sub-verb as `action=`: HUDControlRouter's `settings set` strips `action` but not
    // the CLI parser's positional `_`, which would read as a setting named "_".
    arguments[1] = "action=\(arguments[1])"
} else if command == "action", arguments.count > 1, !arguments[1].contains("=") {
    arguments[1] = "name=\(arguments[1])"
}

if command == "watch" {
    let args = HUDSocketClient.parseArguments(Array(arguments.dropFirst()))
    do {
        _ = try HUDSocketClient(path: path).subscribe(
            events: args["events"].map { $0.split(separator: ",").map(String.init) },
            onEvent: { event in
                if let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) {
                    print(String(decoding: data, as: UTF8.self))
                    fflush(stdout)
                }
            },
            onClose: { exit(0) }
        )
    } catch {
        fail("serversHUD is not running (\(error))")
    }
    dispatchMain()
}

exit(HUDSocketClient.runCLI(path: path, arguments: arguments, appName: "servershud"))
