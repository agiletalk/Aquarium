import Foundation

/// World가 일으키는 바깥 효과. 소리·음악·브라우저·시스템 조회는 플랫폼마다
/// 다르므로 Core는 요청만 하고 실행은 앱이 맡는다.
///
/// World는 메인 루프 스레드에서만 부른다.
public protocol WorldEffects: AnyObject {
    func playTouch()
    func playChime()
    func openSponsor()
    var isMusicPlaying: Bool { get }
    /// 음악을 켜고 끈 뒤 상태줄에 띄울 문구를 돌려준다.
    func toggleMusic() -> String
    /// 곡이 바뀌었으면 새 곡 제목, 아니면 nil.
    func pollNewSongTitle() -> String?
    func systemPrefersDark() -> Bool
    /// 집중(뽀모도로) 완료. 기본은 다른 차임과 같다 — 데스크톱은 이것만 소리를 낸다.
    func playFocusComplete()
}

public extension WorldEffects {
    func playFocusComplete() { playChime() }
}
