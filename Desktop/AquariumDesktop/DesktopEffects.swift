import AppKit
import AquariumAudio
import AquariumCore

/// 바탕화면 어항의 WorldEffects. 상시 켜두는 앱이 수시로 소리를 내면 거슬리므로
/// 효과음은 내지 않는다. 음악은 메뉴에서 켰을 때만 — 터미널과 같은 칩튠 플레이어.
final class DesktopEffects: WorldEffects {
    func playTouch() {}
    func playChime() {}
    func openSponsor() {}
    var isMusicPlaying: Bool { MusicPlayer.shared.isPlaying }
    func toggleMusic() -> String { MusicPlayer.shared.toggle() }
    func pollNewSongTitle() -> String? { MusicPlayer.shared.pollNewTitle() }

    func systemPrefersDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
