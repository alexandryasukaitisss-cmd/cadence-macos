import Foundation

/// JSON file cache for a `MusicLibrarySnapshot`.
///
/// Reads tolerate a missing or corrupt file, so a broken cache never takes the
/// library UI down: `read()` simply returns nil. All file access is serialized
/// through a private serial queue, and writes are atomic replaces, so one
/// writer and one reader may use the same cache instance concurrently and a
/// reader always observes a complete file.
///
/// Dates are encoded as ISO 8601, which keeps whole seconds; sub-second
/// precision of `fetchedAt` is not preserved.
public struct MusicLibraryCache: Sendable {
    private let url: URL
    private let ioQueue: DispatchQueue

    public init(url: URL) {
        self.url = url
        self.ioQueue = DispatchQueue(label: "Cadence.MusicLibraryCache.io")
    }

    /// Returns the cached snapshot, or nil when the cache is missing or corrupt.
    public func read() -> MusicLibrarySnapshot? {
        ioQueue.sync { Self.readSnapshot(at: url) }
    }

    /// Encodes and stores the snapshot atomically, creating parent directories as needed.
    public func write(_ snapshot: MusicLibrarySnapshot) throws {
        try ioQueue.sync { try Self.writeSnapshot(snapshot, to: url) }
    }

    // MARK: - File access (serialized on ioQueue)

    private static func readSnapshot(at url: URL) -> MusicLibrarySnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MusicLibrarySnapshot.self, from: data)
    }

    private static func writeSnapshot(_ snapshot: MusicLibrarySnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
