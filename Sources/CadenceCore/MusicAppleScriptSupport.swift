import CoreServices
import Foundation

// MARK: - Descriptor type codes

/// Apple event descriptor type codes this runtime produces. The SDK no longer
/// exposes the legacy CoreServices constants to Swift, so the four-character
/// codes are declared here. Values come from AEDataModel.h.
private enum DescriptorTypeCodes {
    /// 'type': a type code value, also how `missing value` is delivered.
    static let type = 0x7479_7965 as DescType
    /// 'enum': typeEnumerated, how `cloud status` and `special kind` arrive.
    static let enumerated = 0x656E_756D as DescType
    /// 'long': AppleScript integers.
    static let integer = 0x6C6F_6E67 as DescType
    /// 'shor': AppleScript short integers.
    static let shortInteger = 0x7368_6F72 as DescType
    /// 'bool': NSAppleEventDescriptor(boolean:) and older bridges.
    static let boolean = 0x626F_6F6C as DescType
    /// 'true': AppleScript's constant for true.
    static let trueValue = 0x7472_7565 as DescType
    /// 'fals': AppleScript's constant for false.
    static let falseValue = 0x6661_6C73 as DescType
    /// 'doub': AppleScript reals (typeIEEE64BitFloatingPoint).
    static let double = 0x646F_7562 as DescType
    /// 'sing': 32-bit reals (typeIEEE32BitFloatingPoint).
    static let single = 0x7369_6E67 as DescType
    /// 'msng' as a descriptor type; older runtimes delivered missing values this way.
    static let missingValueType = 0x6D73_6E67 as DescType
    /// 'msng' as the code carried inside a 'type' descriptor; the current runtime's shape.
    static let missingValueCode: FourCharCode = 0x6D73_6E67
}

// MARK: - Error mapping

/// Translates `NSAppleScript` error dictionaries into typed library errors.
enum AppleScriptErrorMapper {
    /// errAENoSuchObject: Music reports this when a track has no artwork.
    static let noSuchObjectNumber = -1728

    static func map(_ dictionary: NSDictionary?) -> MusicLibraryError {
        let number = (dictionary?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        let briefMessage = dictionary?[NSAppleScript.errorBriefMessage] as? String
        let fullMessage = dictionary?[NSAppleScript.errorMessage] as? String
        let message = briefMessage ?? fullMessage ?? "Unknown AppleScript error"
        switch number {
        case -1743: return .notAuthorized   // errAEEventNotPermitted
        case -600: return .musicNotRunning   // procNotFound
        default: return .appleScript(code: number, message: message)
        }
    }
}

// MARK: - Script execution

/// Synchronous `NSAppleScript` execution plus the async wrapper the services use.
/// Execution must be kept off the main thread; callers pass their own serial queue.
enum AppleScriptRunner {
    /// Runs the script synchronously on the current thread.
    static func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw MusicLibraryError.appleScript(code: -2700, message: "AppleScript source could not be created")
        }
        // This SDK returns a non-optional descriptor and signals failure
        // through the error dictionary, which is nil only on success.
        var errorDictionary: NSDictionary?
        let result = script.executeAndReturnError(&errorDictionary)
        if let errorDictionary {
            throw AppleScriptErrorMapper.map(errorDictionary)
        }
        return result
    }

    /// Executes the script on a dedicated serial queue and awaits the result,
    /// so Apple events never block the main thread or a cooperative pool thread.
    static func run(_ source: String, on queue: DispatchQueue) async throws -> NSAppleEventDescriptor {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try execute(source))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Enumerator names

/// Names for the AppleScript enumerators (four-character codes) Music returns
/// for `cloud status` and `special kind`. Codes come from Music.app's scripting
/// definition, so a changed or missing entry degrades to an empty string
/// instead of failing the load.
enum MusicScriptEnumNames {
    static let cloudStatus: [FourCharCode: String] = [
        code("kUnk"): "unknown",
        code("kPur"): "purchased",
        code("kMat"): "matched",
        code("kUpl"): "uploaded",
        code("kRej"): "ineligible",
        code("kRem"): "removed",
        code("kErr"): "error",
        code("kDup"): "duplicate",
        code("kSub"): "subscription",
        code("kPrR"): "prerelease",
        code("kRev"): "no longer available",
        code("kUpP"): "not uploaded",
    ]

    static let playlistSpecialKind: [FourCharCode: String] = [
        code("kNon"): "none",
        code("kSpF"): "folder",
        code("kSpG"): "Genius",
        code("kSpL"): "Library",
        code("kSpZ"): "Music",
        code("kSpM"): "Purchased Music",
    ]

    /// Resolves the code carried by an enumerator or type descriptor.
    static func enumeratorName(for descriptor: NSAppleEventDescriptor, in table: [FourCharCode: String]) -> String? {
        switch descriptor.descriptorType {
        case DescriptorTypeCodes.enumerated:
            return table[descriptor.enumCodeValue]
        case DescriptorTypeCodes.type:
            return table[descriptor.typeCodeValue]
        default:
            return nil
        }
    }

    /// Packs a four-character code string ("kSub") into an Apple event code.
    private static func code(_ string: String) -> FourCharCode {
        var value: FourCharCode = 0
        for scalar in string.unicodeScalars where scalar.value <= 0xFF {
            value = (value << 8) | FourCharCode(scalar.value)
        }
        return value
    }
}

// MARK: - Descriptor reading

/// A typed reader over an AppleScript list descriptor. Indices are zero-based;
/// Apple event list descriptors are one-based internally. Only the typed
/// accessors are used — raw `.data` bytes follow the runtime's internal byte
/// order and must not be parsed by hand.
struct AppleScriptList {
    let descriptor: NSAppleEventDescriptor?
    private let itemCount: Int

    init(_ descriptor: NSAppleEventDescriptor?) {
        self.descriptor = descriptor
        self.itemCount = descriptor?.numberOfItems ?? 0
    }

    var count: Int { itemCount }

    func item(at index: Int) -> NSAppleEventDescriptor? {
        guard let descriptor, index >= 0, index < itemCount else { return nil }
        return descriptor.atIndex(index + 1)
    }

    /// Detects AppleScript `missing value` in either of its historical shapes.
    static func isMissingValue(_ descriptor: NSAppleEventDescriptor) -> Bool {
        if descriptor.descriptorType == DescriptorTypeCodes.missingValueType { return true }
        return descriptor.descriptorType == DescriptorTypeCodes.type
            && descriptor.typeCodeValue == DescriptorTypeCodes.missingValueCode
    }

    /// Reads an AppleScript integer ('long'/'shor'); missing values return nil.
    func int(at index: Int) -> Int? {
        guard let item = item(at: index) else { return nil }
        switch item.descriptorType {
        case DescriptorTypeCodes.integer, DescriptorTypeCodes.shortInteger:
            return Int(item.int32Value)
        default:
            return nil
        }
    }

    /// Reads an AppleScript real ('doub'/'sing'); integers are accepted too.
    func double(at index: Int) -> Double? {
        guard let item = item(at: index) else { return nil }
        switch item.descriptorType {
        case DescriptorTypeCodes.double, DescriptorTypeCodes.single:
            return item.doubleValue
        default:
            return int(at: index).map(Double.init)
        }
    }

    /// Reads an AppleScript boolean ('true'/'fals'/'bool').
    func bool(at index: Int) -> Bool? {
        guard let item = item(at: index) else { return nil }
        switch item.descriptorType {
        case DescriptorTypeCodes.trueValue: return true
        case DescriptorTypeCodes.falseValue: return false
        case DescriptorTypeCodes.boolean: return item.booleanValue
        default: return nil
        }
    }

    /// Reads text. Enumerator and type descriptors carry four-character codes
    /// rather than display text in this runtime, so they resolve through the
    /// table first; the raw code is still better than nothing when the code
    /// is not in the table.
    func string(at index: Int, enumTable: [FourCharCode: String] = [:]) -> String? {
        guard let item = item(at: index), !Self.isMissingValue(item) else { return nil }
        switch item.descriptorType {
        case DescriptorTypeCodes.enumerated, DescriptorTypeCodes.type:
            return MusicScriptEnumNames.enumeratorName(for: item, in: enumTable) ?? item.stringValue
        default:
            return item.stringValue
        }
    }

    /// Reads a Music date ('ldt ' long-date-time); missing dates return nil.
    func date(at index: Int) -> Date? {
        item(at: index)?.dateValue
    }
}

// MARK: - Parsing

/// Result of parsing the track metadata script.
struct AppleScriptTrackMetadata {
    let tracks: [MusicTrack]
    let musicVersion: String?
}

/// Pure mapping from the AppleScript result descriptors to the library models.
/// Nothing here talks to Music; tests feed synthetic descriptor lists.
enum MusicLibraryAppleScriptParser {
    /// Column order of the track metadata script's returned list.
    private enum TrackColumn: Int {
        case databaseIDs = 0
        case persistentIDs = 1
        case titles = 2
        case artists = 3
        case albums = 4
        case albumArtists = 5
        case durations = 6
        case trackNumbers = 7
        case discNumbers = 8
        case years = 9
        case genres = 10
        case playedCounts = 11
        case favoritedFlags = 12
        case cloudStatuses = 13
        case kinds = 14
        case addedDates = 15
        case playedDates = 16
        case musicVersion = 17
    }

    /// Field order inside one playlist record of the playlist script.
    private enum PlaylistField: Int {
        case name = 0
        case trackCount = 1
        case specialKind = 2
        case isFolder = 3
        case trackIDs = 4
        case persistentID = 5
    }

    static func trackMetadata(from root: NSAppleEventDescriptor) -> AppleScriptTrackMetadata {
        func column(_ column: TrackColumn) -> AppleScriptList {
            AppleScriptList(root.atIndex(column.rawValue + 1))
        }

        let databaseIDs = column(.databaseIDs)
        let persistentIDs = column(.persistentIDs)
        let titles = column(.titles)
        let artists = column(.artists)
        let albums = column(.albums)
        let albumArtists = column(.albumArtists)
        let durations = column(.durations)
        let trackNumbers = column(.trackNumbers)
        let discNumbers = column(.discNumbers)
        let years = column(.years)
        let genres = column(.genres)
        let playedCounts = column(.playedCounts)
        let favoritedFlags = column(.favoritedFlags)
        let cloudStatuses = column(.cloudStatuses)
        let kinds = column(.kinds)
        let addedDates = column(.addedDates)
        let playedDates = column(.playedDates)

        // The database ID column anchors the track count; every other column
        // may be shorter or hold missing values without failing the load.
        var tracks: [MusicTrack] = []
        tracks.reserveCapacity(databaseIDs.count)
        for index in 0..<databaseIDs.count {
            guard let id = databaseIDs.int(at: index) else { continue }
            tracks.append(
                MusicTrack(
                    id: id,
                    persistentID: persistentIDs.string(at: index) ?? "",
                    title: titles.string(at: index) ?? "",
                    artist: artists.string(at: index) ?? "",
                    album: albums.string(at: index) ?? "",
                    albumArtist: albumArtists.string(at: index) ?? "",
                    duration: durations.double(at: index) ?? 0,
                    trackNumber: trackNumbers.int(at: index) ?? 0,
                    discNumber: discNumbers.int(at: index) ?? 0,
                    year: years.int(at: index) ?? 0,
                    genre: genres.string(at: index) ?? "",
                    playedCount: playedCounts.int(at: index) ?? 0,
                    favorited: favoritedFlags.bool(at: index) ?? false,
                    cloudStatus: cloudStatuses.string(at: index, enumTable: MusicScriptEnumNames.cloudStatus) ?? "",
                    kind: kinds.string(at: index) ?? "",
                    dateAdded: addedDates.date(at: index),
                    playedDate: playedDates.date(at: index)
                )
            )
        }

        // The version is a bare string descriptor, not a one-item list.
        let musicVersion = root.atIndex(TrackColumn.musicVersion.rawValue + 1).flatMap { descriptor -> String? in
            AppleScriptList.isMissingValue(descriptor) ? nil : descriptor.stringValue
        }

        return AppleScriptTrackMetadata(tracks: tracks, musicVersion: musicVersion)
    }

    static func playlists(from root: NSAppleEventDescriptor) -> [MusicPlaylist] {
        let records = AppleScriptList(root)
        var playlists: [MusicPlaylist] = []
        playlists.reserveCapacity(records.count)
        for recordIndex in 0..<records.count {
            let record = AppleScriptList(records.item(at: recordIndex))
            guard let name = record.string(at: PlaylistField.name.rawValue), !name.isEmpty else { continue }

            let trackIDList = AppleScriptList(record.item(at: PlaylistField.trackIDs.rawValue))
            var trackIDs: [Int] = []
            trackIDs.reserveCapacity(trackIDList.count)
            for trackIndex in 0..<trackIDList.count {
                if let trackID = trackIDList.int(at: trackIndex) { trackIDs.append(trackID) }
            }

            playlists.append(
                MusicPlaylist(
                    persistentID: record.string(at: PlaylistField.persistentID.rawValue) ?? "",
                    name: name,
                    trackCount: record.int(at: PlaylistField.trackCount.rawValue) ?? trackIDs.count,
                    specialKind: record.string(at: PlaylistField.specialKind.rawValue, enumTable: MusicScriptEnumNames.playlistSpecialKind) ?? "none",
                    isFolder: record.bool(at: PlaylistField.isFolder.rawValue) ?? false,
                    trackIDs: trackIDs
                )
            )
        }
        return playlists
    }
}
