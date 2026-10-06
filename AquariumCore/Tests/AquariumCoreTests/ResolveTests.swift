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

    @Test("auto 계절은 9–11월만 가을, 여름과 겹치지 않는다", arguments: 1...12)
    func autoAutumnFollowsCalendar(month: Int) {
        #expect(Resolve.isAutumn(season: .auto, month: month) == (9...11).contains(month))
        #expect(!(Resolve.isAutumn(season: .auto, month: month) && Resolve.isSummer(season: .auto, month: month)))
    }

    @Test("가을 강제는 여름을 끄고, 여름 강제는 가을을 끈다")
    func forcedAutumnIsExclusive() {
        for month in 1...12 {
            #expect(Resolve.isAutumn(season: .autumn, month: month))
            #expect(!Resolve.isSummer(season: .autumn, month: month))
            #expect(!Resolve.isAutumn(season: .summer, month: month))
            #expect(!Resolve.isAutumn(season: .off, month: month))
        }
    }

    @Test("할로윈은 가을 연출이 켜진 10월 31일만")
    func halloween() {
        let day = MonthDay(month: 10, day: 31)
        #expect(Resolve.isHalloween(season: .auto, today: day))
        #expect(Resolve.isHalloween(season: .autumn, today: day))
        #expect(!Resolve.isHalloween(season: .off, today: day))
        #expect(!Resolve.isHalloween(season: .summer, today: day))
        #expect(!Resolve.isHalloween(season: .auto, today: MonthDay(month: 10, day: 30)))
        #expect(!Resolve.isHalloween(season: .autumn, today: MonthDay(month: 3, day: 31)))
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
        #expect(config.debugToday == nil)
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

@Suite("정원 — fishCap")
struct FishCapTests {
    private func world(cap: Int?, lounge: Bool = true) -> World {
        let config = RunConfig(lounge: lounge, ephemeral: true,
                               storage: Storage(saveURL: nil, pollsTerminalQueues: false), fishCap: cap)
        return World(cols: 300, rows: 90, config: config, effects: SilentEffects())
    }

    @Test("nil이면 기존 규칙 — 라운지 120, 일반 40")
    func defaultRule() {
        #expect(world(cap: nil).capacity == 120)
        #expect(world(cap: nil, lounge: false).capacity == 40)
    }

    @Test("정원을 지정하면 그 값, 화면 밀도가 더 작으면 밀도")
    func capApplied() {
        #expect(world(cap: 80).capacity == 80)
        let small = World(cols: 80, rows: 24,
                          config: RunConfig(lounge: true, ephemeral: true,
                                            storage: Storage(saveURL: nil, pollsTerminalQueues: false),
                                            fishCap: 120),
                          effects: SilentEffects())
        #expect(small.capacity == 24) // 80*24/80
    }

    @Test("실행 중에 바꿀 수 있고, 있는 물고기는 그대로")
    func changeAtRuntime() {
        let w = world(cap: 120)
        let before = w.saveState().fish.count
        w.setFishCap(40)
        #expect(w.capacity == 40)
        #expect(w.saveState().fish.count == before)
    }
}

@Suite("MonthDay — AQUARIUM_TODAY 파싱")
struct MonthDayTests {
    @Test("YYYY-MM-DD에서 월·일을 읽는다")
    func parses() {
        #expect(MonthDay(parsing: "2026-10-31") == MonthDay(month: 10, day: 31))
        #expect(MonthDay(parsing: "2026-01-05") == MonthDay(month: 1, day: 5))
    }

    @Test("형식이 틀리면 nil — 실제 날짜로 돌아간다", arguments: [nil, "", "10-31", "2026-13-01", "2026-10-32", "abc-de-fg"])
    func rejects(text: String?) {
        #expect(MonthDay(parsing: text) == nil)
    }

    @Test("터미널 resolve가 AQUARIUM_TODAY를 읽는다")
    func terminalReadsEnvironment() {
        let config = RunConfig.terminal(environment: ["AQUARIUM_TODAY": "2026-10-31"], lounge: false, terminalDark: nil)
        #expect(config.debugToday == MonthDay(month: 10, day: 31))
    }
}

@Suite("Achievements — 세이브 호환")
struct AchievementOrderTests {
    @Test("업적 id는 겹치지 않는다")
    func uniqueIDs() {
        let ids = Achievements.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("가을 업적은 배열 끝에 붙는다 — 기존 순서를 건드리지 않는다")
    func autumnAppended() {
        #expect(Achievements.all.suffix(2).map(\.id) == ["shad_1", "chestnut_1"])
        #expect(Achievements.all[Achievements.all.count - 3].id == "personalityKinds_5")
    }

    @Test("전어 떼 목격 수가 업적 통계로 들어간다")
    func shadStat() {
        #expect(VisitorKind.allCases.last == .shad)
    }
}
