import AppKit
import Foundation

/// Development-only launch hooks. They are compiled out of release builds so
/// the shipped app cannot be asked to write screenshots/logs or skip safety
/// steps through environment variables.
enum DebugSupport {
#if DEBUG
    private static var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    static var disableMusicAutomation: Bool { environment["CADENCE_DISABLE_MUSIC"] == "1" }
    static var skipOnboarding: Bool { environment["CADENCE_SKIP_ONBOARDING"] == "1" }
    static var disableArtwork: Bool { environment["CADENCE_DISABLE_ARTWORK"] == "1" }
    static var disableRemoteArtwork: Bool { environment["CADENCE_DISABLE_REMOTE_ARTWORK"] == "1" }
    static var startWithPodcasts: Bool { environment["CADENCE_START_PODCASTS"] == "1" }
    static var autoplayPodcast: Bool { environment["CADENCE_PODCAST_AUTOPLAY"] == "1" }
    static var showPaletteAtLaunch: Bool { environment["CADENCE_SHOW_PALETTE"] == "1" }
    static var showMiniPlayerAtLaunch: Bool { environment["CADENCE_SHOW_MINI_PLAYER"] == "1" }

    static func scheduleSnapshotIfRequested() {
        guard let path = environment["CADENCE_SNAPSHOT_PATH"], !path.isEmpty else { return }
        log("schedule snapshot onboarding=\(environment["CADENCE_SKIP_ONBOARDING"] ?? "nil") music=\(environment["CADENCE_DISABLE_MUSIC"] ?? "nil") art=\(environment["CADENCE_DISABLE_ARTWORK"] ?? "nil")")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            log("snapshot timer fired")
            captureWindow(to: path)
            if environment["CADENCE_EXIT_AFTER_SNAPSHOT"] == "1" {
                log("exiting after snapshot")
                exit(0)
            }
        }
    }

    static func log(_ message: String) {
        guard environment["CADENCE_DEBUG_LOG"] == "1" else { return }
        let line = "[Cadence] \(Date()) \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/cadence-debug.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private static func captureWindow(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }),
              let view = window.contentView else {
            log("capture: no visible main window")
            return
        }
        log("capture start bounds=\(view.bounds)")
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            log("capture: cannot allocate bitmap")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        log("capture: cacheDisplay done")
        guard let data = rep.representation(using: .png, properties: [:]) else {
            log("capture: cannot encode PNG")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            log("capture: wrote \(path) bytes=\(data.count)")
        } catch {
            log("capture failed: \(error)")
        }
    }
#else
    static var disableMusicAutomation: Bool { false }
    static var skipOnboarding: Bool { false }
    static var disableArtwork: Bool { false }
    static var disableRemoteArtwork: Bool { false }
    static var startWithPodcasts: Bool { false }
    static var autoplayPodcast: Bool { false }
    static var showPaletteAtLaunch: Bool { false }
    static var showMiniPlayerAtLaunch: Bool { false }
    static func scheduleSnapshotIfRequested() {}
    static func log(_ message: String) {}
#endif
}
