import AquariumAudio
import AquariumCore
import Foundation

/// 터미널 앱의 WorldEffects — afplay 효과음, 칩튠 플레이어, `open`, `defaults`.
final class TerminalEffects: WorldEffects {
    func playTouch() { Sound.playTouch() }
    func playChime() { Sound.playChime() }
    func openSponsor() { Support.openInBrowser() }
    var isMusicPlaying: Bool { MusicPlayer.shared.isPlaying }
    func toggleMusic() -> String { MusicPlayer.shared.toggle() }
    func pollNewSongTitle() -> String? { MusicPlayer.shared.pollNewTitle() }

    func systemPrefersDark() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "-g", "AppleInterfaceStyle"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.contains("Dark")
    }
}
