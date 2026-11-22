import Foundation

/// Fetches raw artwork bytes (JPEG/PNG) for a library track through AppleScript.
///
/// This type only reads bytes: the UI layer owns artwork caching by album, and
/// no temporary files are written. Scripts run on a private serial queue.
/// The class is `@unchecked Sendable` because all stored state is immutable
/// and script execution is confined to that queue.
public final class AppleScriptMusicArtworkService: MusicArtworkProviding, @unchecked Sendable {
    private let scriptQueue: DispatchQueue

    public init() {
        self.scriptQueue = DispatchQueue(label: "Cadence.AppleScriptMusicArtworkService")
    }

    /// Returns the track's artwork data, or nil when the track has no artwork.
    public func artworkData(for trackID: Int) async throws -> Data? {
        guard trackID > 0 else { return nil }
        let source = """
        tell application "Music"
            get data of artwork 1 of (first track of library playlist 1 whose database ID is \(trackID))
        end tell
        """
        do {
            let descriptor = try await AppleScriptRunner.run(source, on: scriptQueue)
            guard !AppleScriptList.isMissingValue(descriptor), !descriptor.data.isEmpty else { return nil }
            return descriptor.data
        } catch let error as MusicLibraryError {
            if case let .appleScript(code, _) = error, code == AppleScriptErrorMapper.noSuchObjectNumber {
                // Music reports "object not found" for tracks without artwork.
                return nil
            }
            throw error
        }
    }
}
