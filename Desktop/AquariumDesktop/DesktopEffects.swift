import AppKit
import AquariumCore

/// 바탕화면 어항의 WorldEffects. 상시 켜두는 앱이 수시로 소리를 내면 거슬리므로
/// 효과음은 내지 않는다. 음악은 Step 4(메뉴바)에서 붙인다.
final class DesktopEffects: WorldEffects {
    func playTouch() {}
    func playChime() {}
    func openSponsor() {}
    var isMusicPlaying: Bool { false }
    func toggleMusic() -> String { "" }
    func pollNewSongTitle() -> String? { nil }

    func systemPrefersDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
