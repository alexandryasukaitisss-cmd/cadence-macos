import Foundation
import XCTest
@testable import CadenceCore

/// Pure parser tests over synthetic Apple event descriptors, built with the
/// same constructors the runtime uses. No Apple events are sent to Music from
/// this file.
final class AppleScriptParsingTests: XCTestCase {
    // MARK: - Descriptor builders

    private func list(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let listDescriptor = NSAppleEventDescriptor.list()
        for (index, item) in items.enumerated() {
            listDescriptor.insert(item, at: index + 1)
        }
        return listDescriptor
    }

    private func int(_ value: Int) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(int32: Int32(value))
    }

    private func text(_ value: String) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(string: value)
    }

    private func bool(_ value: Bool) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(boolean: value)
    }

    private func real(_ value: Double) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(double: value)
    }

    private func date(_ value: Date) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(date: value)
    }

    /// `missing value` arrives as a 'type' descriptor carrying the 'msng'
    /// code, byte-packed in the runtime's own storage order (verified against
    /// a real AppleScript result).
    private func missing() -> NSAppleEventDescriptor {
        guard let descriptor = NSAppleEventDescriptor(
            descriptorType: 0x7479_7965,
            data: Data([0x67, 0x6E, 0x73, 0x6D])
        ) else {
            fatalError("missing-value descriptor could not be constructed")
        }
        return descriptor
    }

    /// An AppleScript enumerator descriptor carries its four-character code.
    private func enumerator(_ code: String) -> NSAppleEventDescriptor {
        var value: UInt32 = 0
        for scalar in code.unicodeScalars {
            value = (value << 8) | UInt32(scalar.value)
        }
        return NSAppleEventDescriptor(enumCode: value)
    }

    // MARK: - Track metadata

    func testTrackMetadataParsing() throws {
        let root = list([
            list([int(11), int(12)]),                                // database IDs
            list([text("ABCD1234"), missing()]),                      // persistent IDs
            list([text("First"), text("Second")]),                    // titles
            list([text("Artist"), missing()]),                        // artists
            list([text("Album"), text("Album")]),                     // albums
            list([missing(), text("Album Artist")]),                  // album artists
            list([real(210.5), real(184)]),                           // durations
            list([int(1), int(2)]),                                    // track numbers
            list([int(1), missing()]),                                 // disc numbers
            list([int(2024), int(0)]),                                 // years
            list([text("Rock"), missing()]),                           // genres
            list([int(5), int(0)]),                                    // played counts
            list([bool(true), bool(false)]),                            // favorited
            list([enumerator("kSub"), missing()]),                     // cloud statuses
            list([text("AAC audio file"), text("Purchased AAC")]),    // kinds
            list([date(Date(timeIntervalSince1970: 1_700_000_000)), missing()]),   // date added
            list([missing(), date(Date(timeIntervalSince1970: 1_700_000_500))]),   // played dates
            text("1.5.1")                                               // Music version
        ])

        let metadata = MusicLibraryAppleScriptParser.trackMetadata(from: root)

        XCTAssertEqual(metadata.musicVersion, "1.5.1")
        XCTAssertEqual(metadata.tracks.count, 2)

        let first = try XCTUnwrap(metadata.tracks.first)
        XCTAssertEqual(first.id, 11)
        XCTAssertEqual(first.persistentID, "ABCD1234")
        XCTAssertEqual(first.title, "First")
        XCTAssertEqual(first.artist, "Artist")
        XCTAssertEqual(first.album, "Album")
        XCTAssertEqual(first.albumArtist, "")
        XCTAssertEqual(first.duration, 210.5)
        XCTAssertEqual(first.trackNumber, 1)
        XCTAssertEqual(first.discNumber, 1)
        XCTAssertEqual(first.year, 2024)
        XCTAssertEqual(first.genre, "Rock")
        XCTAssertEqual(first.playedCount, 5)
        XCTAssertTrue(first.favorited)
        XCTAssertEqual(first.cloudStatus, "subscription")
        XCTAssertEqual(first.kind, "AAC audio file")
        XCTAssertEqual(first.dateAdded, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(first.playedDate)

        let second = try XCTUnwrap(metadata.tracks.last)
        XCTAssertEqual(second.id, 12)
        XCTAssertEqual(second.persistentID, "")
        XCTAssertEqual(second.artist, "")
        XCTAssertEqual(second.albumArtist, "Album Artist")
        XCTAssertEqual(second.duration, 184)
        XCTAssertEqual(second.discNumber, 0)
        XCTAssertEqual(second.cloudStatus, "")
        XCTAssertFalse(second.favorited)
        XCTAssertNil(second.dateAdded)
        XCTAssertEqual(second.playedDate, Date(timeIntervalSince1970: 1_700_000_500))
    }

    /// Short or absent columns must not fail the load; defaults fill the gaps.
    func testShortColumnsFallBackToDefaults() {
        let root = list([
            list([int(30), int(31)]),   // database IDs
            list([]),                    // persistent IDs missing entirely
            list([text("Only")]),        // titles shorter than the ID column
            list([]), list([]), list([]),
            list([]), list([]), list([]), list([]), list([]), list([]),
            list([]), list([]), list([]), list([]),
            list([]), list([]),
            missing()                    // no Music version
        ])

        let metadata = MusicLibraryAppleScriptParser.trackMetadata(from: root)

        XCTAssertNil(metadata.musicVersion)
        XCTAssertEqual(metadata.tracks.count, 2)
        XCTAssertEqual(metadata.tracks[1].id, 31)
        XCTAssertEqual(metadata.tracks[1].title, "")
        XCTAssertEqual(metadata.tracks[1].persistentID, "")
        XCTAssertEqual(metadata.tracks[1].duration, 0)
        XCTAssertEqual(metadata.tracks[1].playedCount, 0)
        XCTAssertFalse(metadata.tracks[1].favorited)
        XCTAssertNil(metadata.tracks[1].dateAdded)
    }

    // MARK: - Playlists

    func testPlaylistParsing() throws {
        let root = list([
            list([text("Library"), int(3), text("Library"), bool(false), list([int(1), int(2), int(3)]), text("PID-LIB")]),
            list([text("Папка"), int(0), text("folder"), bool(true), list([]), text("PID-FOLDER")]),
            list([text("Road"), int(2), text("none"), bool(false), list([int(7), int(3)]), text("PID-ROAD")]),
            list([text(""), int(0), text("none"), bool(false), list([]), text("PID-EMPTY")])
        ])

        let playlists = MusicLibraryAppleScriptParser.playlists(from: root)

        // The unnamed record is skipped.
        XCTAssertEqual(playlists.count, 3)

        let library = try XCTUnwrap(playlists.first { $0.name == "Library" })
        XCTAssertTrue(library.isLibrary)
        XCTAssertFalse(library.isFolder)
        XCTAssertEqual(library.trackCount, 3)
        XCTAssertEqual(library.trackIDs, [1, 2, 3])
        XCTAssertEqual(library.persistentID, "PID-LIB")
        XCTAssertEqual(library.id, "PID-LIB")

        let folder = try XCTUnwrap(playlists.first { $0.name == "Папка" })
        XCTAssertTrue(folder.isFolder)
        XCTAssertTrue(folder.trackIDs.isEmpty)
        XCTAssertEqual(folder.trackCount, 0)

        let road = try XCTUnwrap(playlists.first { $0.name == "Road" })
        XCTAssertEqual(road.specialKind, "none")
        XCTAssertEqual(road.trackIDs, [7, 3])
        XCTAssertEqual(road.trackCount, 2)
        XCTAssertEqual(road.persistentID, "PID-ROAD")
        XCTAssertEqual(road.id, "PID-ROAD")
    }

    func testPlaylistWithoutPersistentIDFallsBackToNormalizedName() throws {
        let root = list([
            list([text("Road"), int(1), text("none"), bool(false), list([int(7)])])
        ])

        let playlists = MusicLibraryAppleScriptParser.playlists(from: root)

        let road = try XCTUnwrap(playlists.first)
        XCTAssertEqual(road.persistentID, "")
        XCTAssertEqual(road.id, "road")
    }

    /// Enumerator descriptors resolve through the code table when the script
    /// could not coerce them to text.
    func testPlaylistSpecialKindFromEnumeratorCode() throws {
        let root = list([
            list([text("Плейлист"), int(0), enumerator("kSpZ"), bool(false), list([]), text("PID-MUSIC")])
        ])

        let playlists = MusicLibraryAppleScriptParser.playlists(from: root)

        let playlist = try XCTUnwrap(playlists.first)
        XCTAssertEqual(playlist.specialKind, "Music")
        XCTAssertTrue(playlist.isMusic)
    }

    // MARK: - Error mapping

    func testErrorMapping() {
        if case .notAuthorized = AppleScriptErrorMapper.map(dictionary(number: -1743)) {
            // expected
        } else {
            XCTFail("Expected notAuthorized for -1743")
        }

        if case .musicNotRunning = AppleScriptErrorMapper.map(dictionary(number: -600)) {
            // expected
        } else {
            XCTFail("Expected musicNotRunning for -600")
        }

        if case let .appleScript(code, message) = AppleScriptErrorMapper.map(dictionary(number: -1728)) {
            XCTAssertEqual(code, -1728)
            XCTAssertTrue(message.contains("Can't get"))
        } else {
            XCTFail("Expected appleScript for -1728")
        }

        if case let .appleScript(code, _) = AppleScriptErrorMapper.map(nil) {
            XCTAssertEqual(code, 0)
        } else {
            XCTFail("Expected appleScript fallback for a missing dictionary")
        }
    }

    private func dictionary(number: Int, message: String = "Can't get artwork 1") -> NSDictionary {
        NSDictionary(dictionary: [
            NSAppleScript.errorNumber: NSNumber(value: number),
            NSAppleScript.errorBriefMessage: message
        ])
    }
}
