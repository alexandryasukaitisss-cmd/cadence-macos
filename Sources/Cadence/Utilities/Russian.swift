import Foundation

enum RU {
    static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let value = abs(count) % 100
        if (11...14).contains(value) { return many }
        switch value % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }

    static func tracks(_ count: Int) -> String {
        "\(count) \(plural(count, "трек", "трека", "треков"))"
    }

    static func albums(_ count: Int) -> String {
        "\(count) \(plural(count, "альбом", "альбома", "альбомов"))"
    }

    static func artists(_ count: Int) -> String {
        "\(count) \(plural(count, "исполнитель", "исполнителя", "исполнителей"))"
    }

    static func playlists(_ count: Int) -> String {
        "\(count) \(plural(count, "плейлист", "плейлиста", "плейлистов"))"
    }
}
