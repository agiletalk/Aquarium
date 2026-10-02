import AppKit
import AquariumCore

/// 첫 실행 때 터미널 어항(~/.aquarium.json)을 데스크톱으로 복사할지 묻는다.
///
/// 복사이지 이동이 아니다 — 터미널 어항은 그대로 남고, 이후 두 어항은 따로 자란다.
/// v0.1은 두 앱이 같은 세이브를 동시에 쓰지 않는다(덮어쓰기 경합). 상태 공유는 v0.3.
enum TerminalImport {
    static func offerIfNeeded() {
        guard !Settings.importAsked,
              !FileManager.default.fileExists(atPath: WallpaperController.saveURL.path),
              let terminal = SaveStore.load(), !terminal.fish.isEmpty else { return }
        Settings.importAsked = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = t("터미널 어항을 가져올까요?",
                              "Bring over your terminal aquarium?")
        alert.informativeText = t(
            "터미널에서 키우던 물고기 \(terminal.fish.count)마리를 바탕화면 어항으로 복사합니다. "
                + "터미널 어항은 그대로 남고, 이후 두 어항은 따로 자랍니다.",
            "Copies your \(terminal.fish.count) terminal fish to the desktop tank. "
                + "The terminal tank stays as it is, and from now on the two tanks grow separately.")
        alert.addButton(withTitle: t("가져오기", "Bring Over"))
        alert.addButton(withTitle: t("새 어항으로 시작", "Start Fresh"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        SaveStore.write(copy(of: terminal), to: WallpaperController.saveURL)
    }

    /// 물고기 id를 전부 새로 발급한다 — 입양 중복 차단이 id 기준이라, 그대로 두면
    /// 나중에 터미널 물고기를 데스크톱으로 분양할 때 조용히 버려진다.
    /// savedAt을 지금으로 — 안 바꾸면 양쪽이 같은 오프라인 출생을 한 번씩 계산한다.
    static func copy(of save: SaveState) -> SaveState {
        var copy = save
        copy.savedAt = Date().timeIntervalSince1970
        for i in copy.fish.indices { copy.fish[i].id = UUID().uuidString }
        return copy
    }
}
