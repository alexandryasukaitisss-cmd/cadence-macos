import AppKit
import SwiftUI

/// Public v0.1 does not embed the Apple Podcasts web player. It opens the
/// official catalog in the user's browser, so Cadence never sees an Apple
/// Account session or injects scripts into Apple's page.
struct PodcastsExternalView: View {
    @State private var region = Locale.current.region?.identifier.lowercased() ?? "us"

    private var catalogURL: URL {
        URL(string: "https://podcasts.apple.com/\(region)/new") ?? URL(string: "https://podcasts.apple.com/")!
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "mic.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.podcastAccent)
            Text("Apple Podcasts")
                .font(.system(size: 24, weight: .bold))
            Text("Cadence открывает официальный каталог Apple Podcasts в браузере. Встроенного плеера, входа и синхронизации в этой версии нет.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                NSWorkspace.shared.open(catalogURL)
            } label: {
                Label("Открыть Apple Podcasts", systemImage: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(height: 34)
                    .padding(.horizontal, 18)
                    .background(Theme.podcastAccent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Text("Cadence не связан с Apple. Apple Podcasts — товарный знак Apple Inc.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
