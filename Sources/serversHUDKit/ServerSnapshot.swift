import Foundation

/// One scan. Diffing two tells the UI which servers just appeared (highlighted) and which just
/// went away. Identity is the pid plus its ports: a process that starts listening on another
/// port counts as added again.
public struct ServerSnapshot: Equatable, Sendable {
    public var servers: [Server]
    public var takenAt: Date

    public init(servers: [Server], takenAt: Date = Date()) {
        self.servers = servers
        self.takenAt = takenAt
    }

    public struct Key: Hashable, Sendable {
        public var pid: Int32
        public var ports: [Int]
    }

    public static func key(_ server: Server) -> Key { Key(pid: server.pid, ports: server.ports) }

    public struct Diff: Equatable, Sendable {
        public var added: [Server]
        public var removed: [Server]
        public var isEmpty: Bool { added.isEmpty && removed.isEmpty }
        public var addedPIDs: Set<Int32> { Set(added.map(\.pid)) }
    }

    /// Changes since `previous`. With no previous scan nothing counts as added (the first scan
    /// is not news).
    public func diff(since previous: ServerSnapshot?) -> Diff {
        guard let previous else { return Diff(added: [], removed: []) }
        let old = Set(previous.servers.map(Self.key))
        let new = Set(servers.map(Self.key))
        return Diff(added: servers.filter { !old.contains(Self.key($0)) },
                    removed: previous.servers.filter { !new.contains(Self.key($0)) })
    }
}
