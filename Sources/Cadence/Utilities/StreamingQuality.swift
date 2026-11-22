import Foundation

/// Music playback is delegated to Music.app, so audio quality is owned by
/// Music.app. This helper reads its preferences for display only; Cadence
/// never rewrites another app's audio settings.
enum StreamingQuality {
    private static var musicDefaults: UserDefaults? {
        UserDefaults(suiteName: "com.apple.Music")
    }

    static var losslessEnabled: Bool {
        musicDefaults?.bool(forKey: "losslessEnabled") ?? false
    }

    static var atmosDownloadsEnabled: Bool {
        musicDefaults?.bool(forKey: "downloadDolbyAtmos") ?? false
    }

    static var streamQualityCode: Int {
        musicDefaults?.integer(forKey: "preferredStreamPlaybackAudioQuality") ?? 0
    }

    static var musicSummary: String {
        var parts: [String] = []
        if losslessEnabled { parts.append("Lossless включён") }
        if atmosDownloadsEnabled { parts.append("Dolby Atmos включён") }
        return parts.isEmpty ? "Профиль Music.app" : parts.joined(separator: " · ")
    }
}
