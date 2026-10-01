import Foundation
import Testing
@testable import AquariumCore

@Suite("Resolve — 시각 → 연출 판정")
struct ResolveTests {
    @Test("auto 계절은 6–8월만 여름", arguments: 1...12)
    func autoSummerFollowsCalendar(month: Int) {
        #expect(Resolve.isSummer(season: .auto, month: month) == (6...8).contains(month))
    }

    @Test("강제 계절은 달력을 무시한다")
    func forcedSeasonIgnoresMonth() {
        for month in 1...12 {
            #expect(Resolve.isSummer(season: .summer, month: month))
            #expect(!Resolve.isSummer(season: .off, month: month))
        }
    }

    @Test("밤 판정 경계 — 19시부터 밤, 7시부터 낮", arguments: [
        (6, true), (7, false), (18, false), (19, true), (0, true), (12, false),
    ])
    func nightHours(hour: Int, night: Bool) {
        #expect(Resolve.isEnvNight(hour: hour, dark: false) == night)
    }

    @Test("어두운 배경이면 낮 시간에도 밤")
    func darkBackgroundIsNight() {
        for hour in 0..<24 { #expect(Resolve.isEnvNight(hour: hour, dark: true)) }
    }
}

@Suite("RunConfig — 터미널 resolve")
struct RunConfigTests {
    @Test("환경 변수가 없으면 탈출구는 전부 꺼진다")
    func defaultsWithoutEnvironment() {
        let config = RunConfig.terminal(environment: [:], lounge: false, terminalDark: nil)
        #expect(!config.loungeFast)
        #expect(config.debugVisitor == nil)
        #expect(!config.ephemeral)
        #expect(config.storage.pollsTerminalQueues)
        #expect(config.storage.saveURL == SaveStore.fileURL)
    }

    @Test("AQUARIUM_LOUNGE_FAST는 값이 비어 있어도 켜진다 (존재만 본다)")
    func loungeFastIsPresenceOnly() {
        let config = RunConfig.terminal(environment: ["AQUARIUM_LOUNGE_FAST": ""],
                                        lounge: true, terminalDark: true)
        #expect(config.loungeFast)
        #expect(config.lounge)
        #expect(config.terminalDark == true)
    }

    @Test("AQUARIUM_VISITOR는 그대로 넘긴다")
    func visitorPassthrough() {
        let config = RunConfig.terminal(environment: ["AQUARIUM_VISITOR": "whale"],
                                        lounge: false, terminalDark: nil)
        #expect(config.debugVisitor == "whale")
    }
}

/// 소리·브라우저 없이 World를 띄우는 스텁.
final class SilentEffects: WorldEffects {
    func playTouch() {}
    func playChime() {}
    func openSponsor() {}
    var isMusicPlaying: Bool { false }
    func toggleMusic() -> String { "" }
    func pollNewSongTitle() -> String? { nil }
    func systemPrefersDark() -> Bool { false }
}

@Suite("World — 렌더러 중립 출력")
struct WorldOutputTests {
    private func makeWorld(lounge: Bool) -> World {
        let config = RunConfig(lounge: lounge, ephemeral: true,
                               storage: Storage(saveURL: nil, pollsTerminalQueues: false))
        return World(cols: 80, rows: 24, config: config, effects: SilentEffects())
    }

    @Test("hints: false면 안내 칸이 구분자째 빠진다")
    func hintsCanBeDropped() {
        for lounge in [false, true] {
            let world = makeWorld(lounge: lounge)
            let hintTexts = Set([L10n.helpLine]
                + (0..<L10n.loungeHintCount(clap: false)).map { L10n.loungeHint($0) })
            let with = world.statusSegments(hints: true)
            let without = world.statusSegments(hints: false)
            #expect(with.count == without.count + 2)
            #expect(with.contains { hintTexts.contains($0.text) })
            #expect(!without.contains { hintTexts.contains($0.text) })
        }
    }

    @Test("그리드는 상태줄 한 줄을 뺀 크기")
    func gridSize() {
        let grid = makeWorld(lounge: false).composeGrid()
        #expect(grid.count == 23)
        #expect(grid.allSatisfy { $0.count == 80 })
    }
}
