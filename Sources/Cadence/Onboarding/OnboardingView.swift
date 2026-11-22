import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.musicAccent, Theme.podcastAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "waveform")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 78, height: 78)
                .shadow(color: Theme.musicAccent.opacity(0.28), radius: 22, y: 10)

                Text("Cadence")
                    .font(.system(size: 34, weight: .bold))
                Text("Apple Music и подкасты. Без лишнего.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 34)
            .padding(.bottom, 26)

            VStack(spacing: 10) {
                feature(
                    icon: "music.note",
                    color: Theme.musicAccent,
                    title: "Ваша медиатека Music",
                    text: "Cadence читает медиатеку и управляет Music.app. Воспроизведение по подписке остаётся в Music; доступ автоматизации нужен один раз."
                )
                feature(
                    icon: "mic.fill",
                    color: Theme.podcastAccent,
                    title: "Apple Podcasts по ссылке",
                    text: "Официальный каталог Apple Podcasts открывается в браузере. Cadence не принимает данные аккаунта Apple и не встраивает веб-плеер."
                )
                feature(
                    icon: "bolt.fill",
                    color: .orange,
                    title: "Быстро, по-маковски",
                    text: "⌘K, мини-плеер, меню-бар и нативные списки. Никакого Electron и фоновых серверов."
                )
            }
            .padding(.horizontal, 32)

            Text("Cadence использует Music.app для воспроизведения и медиатеки. Подкасты открываются в браузере; встроенный вход и синхронизация в эту версию не входят.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
                .padding(.top, 18)

            Spacer(minLength: 16)

            VStack(spacing: 8) {
                Button {
                    model.completeOnboarding()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "link")
                        Text("Подключить Music и начать")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Theme.musicAccent, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    model.skipOnboarding()
                    model.selectSource(.podcasts)
                } label: {
                    Text("Продолжить без Music")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
                .buttonStyle(.plain)

                Text("Данные остаются на этом Mac. Без телеметрии.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 560, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .interactiveDismissDisabled()
    }

    private func feature(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .cardSurface(cornerRadius: 12)
    }
}
