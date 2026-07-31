import Foundation

struct Cell {
    var ch: Character = " "
    var color: UInt8 = 252
    var glow: Bool = false // glowing cells skip night-time dimming
}

enum Lighting: String {
    case auto, day, night
}

/// 계절 테마 — 조명(Lighting)과 독립된 축. 세이브/CLI 표기는 "none".
enum Season: String {
    case auto, off = "none", summer
}

struct Species {
    let right: [Character]
    let left: [Character]
    let striped: Bool
    var speed: ClosedRange<Double> = 0.15...0.4
}

// index 0 is the baby fish; adults are 1 and up
let allSpecies: [Species] = [
    Species(right: Array("><>"), left: Array("<><"), striped: false),
    Species(right: Array("><(°>"), left: Array("<°)><"), striped: false),
    Species(right: Array("><((°>"), left: Array("<°))><"), striped: false),
    Species(right: Array("><(((°>"), left: Array("<°)))><"), striped: false),
    Species(right: Array("><|||°>"), left: Array("<°|||><"), striped: true),
    Species(right: Array("><^^^°>"), left: Array("<°^^^><"), striped: true),
    Species(right: Array("><}}}°>"), left: Array("<°{{{><"), striped: true),
    Species(right: Array(">-=(((°>"), left: Array("<°)))=-<"), striped: false, speed: 0.3...0.6),
    Species(right: Array("><(((°=>"), left: Array("<=°)))><"), striped: false, speed: 0.3...0.6),
    Species(right: Array("~~(((°>"), left: Array("<°)))~~"), striped: false, speed: 0.08...0.18),
    Species(right: Array(">->"), left: Array("<-<"), striped: false, speed: 0.35...0.65),
    // 크기·모양 다양화 (v2.8.0) — 반드시 배열 끝에 append (기존 세이브 인덱스 보존)
    Species(right: Array("><========°>"), left: Array("<°========><"), striped: false, speed: 0.12...0.3),   // 갈치 (긴 리본)
    Species(right: Array("°>"), left: Array("<°"), striped: false, speed: 0.4...0.7),                        // 치어 (초소형)
    Species(right: Array("<((°))>"), left: Array("<((°))>"), striped: false, speed: 0.1...0.22),             // 가오리풍 마름모
    Species(right: Array("<(((°>-*"), left: Array("*-<°)))>"), striped: false, speed: 0.08...0.2),           // 아귀 (등불)
    Species(right: Array("<*(°)*>"), left: Array("<*(°)*>"), striped: false, speed: 0.1...0.22),             // 복어 (가시공)
    Species(right: Array("<°VVV>"), left: Array("<VVV°>"), striped: false, speed: 0.2...0.45),               // 큰입 (이빨)
]

let fishPalette: [UInt8] = [196, 202, 208, 214, 220, 226, 201, 213, 199, 51, 45, 39, 118, 82, 141, 129]

/// 희귀 변종 — 종(species)과 독립된 시각 오버레이 레이어
enum Morph: Int { case normal, rainbow, glowing, golden, shadow }
let rareMorphs: [Morph] = [.rainbow, .glowing, .golden, .shadow]
let rainbowPalette: [UInt8] = [196, 208, 226, 46, 51, 201]

/// 성격 — 태어날 때 정해지는 영구 기질 (이동/반응을 다르게)
enum Personality: Int, CaseIterable { case shy, greedy, playful, lazy, bold }

/// 기분 — 현재 상황에서 파생되는 표시 전용 상태 (저장 안 함)
enum Mood { case sleepy, eating, idle }

/// 을/를 — final-consonant(받침) aware object particle
func objectParticle(_ name: String) -> String {
    guard let scalar = name.unicodeScalars.last, (0xAC00...0xD7A3).contains(scalar.value) else { return "를" }
    return (scalar.value - 0xAC00) % 28 == 0 ? "를" : "을"
}

/// 이/가 — final-consonant(받침) aware subject particle
func subjectParticle(_ name: String) -> String {
    guard let scalar = name.unicodeScalars.last, (0xAC00...0xD7A3).contains(scalar.value) else { return "가" }
    return (scalar.value - 0xAC00) % 28 == 0 ? "가" : "이"
}

struct Fish {
    var x: Double
    var y: Double
    var vy: Double = 0
    var dir: Double // -1 (left) or 1 (right)
    var speed: Double
    var species: Int
    var color: UInt8
    var color2: UInt8 = 231
    var growAt: Double? // nil means adult
    var eaten: Int = 0
    var name: String = ""
    var bornAtEpoch: Double = 0 // wall-clock epoch
    var panicUntil: Double = 0  // darting away after being touched
    /// 입양 물고기의 입장 연출 — systemUptime 데드라인.
    /// `now < enteringUntil`이 곧 "아직 어항 밖에서 들어오는 중" 플래그다.
    /// 별도 Bool을 두지 않는 이유: 데드라인이 지나면 updateFish의 하드 스냅이
    /// 알아서 어항 안으로 끌어당기므로, 리사이즈 등으로 영영 못 들어오는
    /// 경우의 안전장치가 공짜로 붙는다. 저장하지 않는다(FishState에 좌표가
    /// 아예 없어서 원리적으로 샐 수 없다).
    var enteringUntil: Double = 0
    var id: String = UUID().uuidString
    var origin: [String] = []   // 거쳐온 어항들 (여권)
    var morph: Morph = .normal  // 희귀 변종
    var personality: Personality = .shy // 영구 기질

    var art: [Character] { dir > 0 ? allSpecies[species].right : allSpecies[species].left }
    var mouthX: Double { dir > 0 ? x + Double(art.count - 1) : x }
}

struct Bubble {
    var x: Double
    var y: Double
    var phase: Double
    var speed: Double
}

enum FoodKind {
    case pellet, watermelon
}

struct Food {
    var x: Double
    var y: Double
    var vy: Double
    var restingSince: Double?
    var kind: FoodKind = .pellet // 여름 수박 변형
}

struct Weed {
    var x: Int
    var height: Int
    var phase: Double
}

struct Shrimp {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var bornAt: Double
}

enum VisitorKind: String, CaseIterable {
    case whale, turtle, octopus, sunfish
}

let whaleArtRight: [[Character]] = [
    "     .-'             ",
    "'--./ /     _.---.   ",
    "'-,  (__..-`       \\ ",
    "   \\          o     |",
    "    `,.__.   ,__.--/ ",
    "      '._/_.'___.-`  ",
].map(Array.init)

let whaleArtLeft: [[Character]] = [
    "             `-.     ",
    "   .---._     \\ \\.--`",
    " /       '-..__)  ,-`",
    "|     o          /   ",
    " \\--.__,   .__.,'    ",
    "  '-.___`._\\_.`      ",
].map(Array.init)

// 개복치 — 여름 손님. 위아래 지느러미가 긴 원반형 몸통
let sunfishArtRight: [[Character]] = [
    "   /\\  ",
    "  /  \\ ",
    " (  °_>",
    "  \\  / ",
    "   \\/  ",
].map(Array.init)

let sunfishArtLeft: [[Character]] = [
    "  /\\   ",
    " /  \\  ",
    "<_°  ) ",
    " \\  /  ",
    "  \\/   ",
].map(Array.init)

struct Visitor {
    var kind: VisitorKind
    var x: Double
    var y: Double
    var dir: Double
    var departAt: Double? // octopus leaves on a timer
}

struct Snail {
    var x: Double
    var dir: Double
    var pauseUntil: Double = 0
}

enum CrabMode {
    case walking, pausing, waving
}

struct Crab {
    var x: Double
    var dir: Double
    var mode: CrabMode = .walking
    var modeUntil: Double = 0
}

struct Jellyfish {
    var x: Double
    var y: Double
    var vy: Double = 0
    var phase: Double
    var driftSeed: Double

    // Pulse cycle: contract (jet upward) then relax (drift down)
    func isContracted(at now: Double) -> Bool {
        let cycle = 2.6
        return (now + phase).truncatingRemainder(dividingBy: cycle) / cycle < 0.35
    }
}

final class World {
    private(set) var cols: Int
    private(set) var rows: Int

    var fish: [Fish] = []
    var bubbles: [Bubble] = []
    var food: [Food] = []
    var weeds: [Weed] = []
    var jellyfish: [Jellyfish] = []
    var snails: [Snail] = []
    var crabs: [Crab] = []
    var shrimp: [Shrimp] = []
    var visitor: Visitor?
    private var inkCloud: (x: Double, y: Double, bornAt: Double)?
    private var nextVisitorAt: Double = 0
    private var nextAutoFeedAt: Double = 0
    private var nextEvolveAt: Double = 0
    private var nextQRAt: Double = 0
    private var qrShownUntil: Double = 0
    /// 모듈 격자는 페이로드가 고정이라 한 번만 만든다 (매 프레임 CoreImage를 돌릴 순 없다).
    private lazy var qrModules: [[Bool]]? = QRCode.modules(for: Self.loungeQRPayload)

    /// 공개 레포에 사내 채널 주소를 박을 수 없으니 주소는 주입받는다.
    /// 라운지 맥에서 env 한 줄만 바꾸면 되고 재빌드가 필요 없다.
    ///
    /// 기본값에서 "https://"를 뺀 건 코드 크기 때문이다. 8자가 줄면서 QR 버전이
    /// 3→2로 내려가 화면에서 33x17 → 29x15가 된다. 폰 카메라는 스킴 없는 도메인도
    /// 링크로 인식한다. 주소가 길수록 QR이 커지므로 env로 바꿀 때도 짧을수록 좋다.
    static var loungeQRPayload: String {
        let env = ProcessInfo.processInfo.environment["AQUARIUM_LOUNGE_QR"] ?? ""
        return env.isEmpty ? "github.com/agiletalk/Aquarium" : env
    }
    private var visitorSeen: [String: Int] = [:]
    private let debugVisitor = ProcessInfo.processInfo.environment["AQUARIUM_VISITOR"]

    private var usedNames: Set<String> = []
    private(set) var rosterOpen = false
    private(set) var mailboxOpen = false
    private(set) var sponsorOpen = false
    private var travelers: [Traveler] = []
    private var mailbox: [Postcard] = []
    private var nextPostcardCheck: Double = 0
    private var nowEpoch: Double { Date().timeIntervalSince1970 }

    private var focusUntil: Double? // systemUptime deadline of the running pomodoro
    private var focusDone = 0       // completed sessions, persisted
    private var commitRewards = 0   // total commit rewards, persisted
    private var nextInboxCheck: Double = 0
    private var stats: [String: Int] = [:]        // achievement counters
    private var unlocked: Set<String> = []        // unlocked achievement ids
    private var nextAchvCheck: Double = 0
    private var wasNight = false
    private func bump(_ key: String, _ n: Int = 1) { stats[key, default: 0] += n }

    private var chestX: Int? // left column of the chest; nil when the tank is too narrow
    private var chestOpenUntil: Double = 0
    private var chestNextOpen: Double = 0

    private var message = ""
    private var messageUntil: Double = 0
    private let startTime: Double
    private var nextBreed: Double = 0
    private var tick = 0

    private(set) var lighting: Lighting = .auto
    private let terminalDark: Bool?   // OSC 11 answer captured at startup
    private var envNight = false      // auto-mode verdict, refreshed periodically
    private var nextEnvCheck: Double = 0
    private var nextAutosave: Double = 0
    private var tankBornAt: Double = 0 // wall-clock epoch
    private let ephemeral: Bool        // card rendering: never write the save file

    private(set) var season: Season = .auto

    /// 라운지 전시 모드 — 무인 상설 전시용. Lighting·Season과 직교하며 세이브에 남지 않는다
    /// (전시 맥의 실행 옵션이지 어항의 속성이 아니다).
    private(set) var lounge = false

    /// 라운지 타이머(번식 2~3일, 진화 6~12시간)는 눈으로 검증할 방법이 없어 압축 배율을 둔다.
    /// AQUARIUM_VISITOR와 같은 성격의 테스트용 탈출구 — --help·README에는 싣지 않는다.
    private let loungeFast = ProcessInfo.processInfo.environment["AQUARIUM_LOUNGE_FAST"] != nil
    private var loungeScale: Double { loungeFast ? 1.0 / 1200 : 1 }

    var isNight: Bool { lighting == .night || (lighting == .auto && envNight) }

    /// 여름 판정 — auto면 달력 기준 6–8월. isNight와 직교한다(여름 밤엔 별/달이 그대로).
    var isSummer: Bool {
        switch season {
        case .summer: return true
        case .off: return false
        case .auto: return (6...8).contains(Calendar.current.component(.month, from: Date()))
        }
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    // Vertical layout (0-indexed grid rows; the last terminal row is the status line)
    private var gridRows: Int { rows - 1 }
    private var surfaceRow: Int { 1 }
    private var bottomBorderRow: Int { gridRows - 1 }
    private var sandRow: Int { gridRows - 2 }
    private var swimMinRow: Int { 2 }
    private var swimMaxRow: Int { sandRow - 1 }

    /// 밀도 공식(cols*rows/80)은 그대로 두고 천장만 올린다 — 화면이 커져도 물고기
    /// 점유율은 일정하고, 대형 전시 디스플레이에서만 40마리 상한이 풀린다.
    private var maxFish: Int { max(8, min(lounge ? 120 : 40, cols * rows / 80)) }

    /// 라운지 어항은 몇 주~몇 달에 걸쳐 자라야 전시 서사가 된다. 15~25분 → 2~3일.
    private var breedInterval: ClosedRange<Double> {
        let base: ClosedRange<Double> = lounge ? 172_800...259_200 : 900...1500
        guard lounge else { return base }
        return (base.lowerBound * loungeScale)...(base.upperBound * loungeScale)
    }

    init(cols: Int, rows: Int, terminalDark: Bool? = nil, restoring save: SaveState? = nil,
         ephemeral: Bool = false, lounge: Bool = false) {
        self.cols = cols
        self.rows = rows
        self.terminalDark = terminalDark
        self.ephemeral = ephemeral
        self.lounge = lounge
        startTime = ProcessInfo.processInfo.systemUptime
        nextBreed = startTime + Double.random(in: breedInterval)
        tankBornAt = Date().timeIntervalSince1970
        nextVisitorAt = startTime + (debugVisitor != nil
            ? 4
            : lounge ? Double.random(in: 20...45) : Double.random(in: 120...300))
        if lounge {
            nextAutoFeedAt = startTime + Double.random(in: 20...40) * loungeScale
            nextEvolveAt = startTime + Double.random(in: 21_600...43_200) * loungeScale
            nextQRAt = startTime + 30
        }
        plantWeeds()
        placeChest()
        spawnJellyfish()
        spawnCleanupCrew()
        if let save, !save.fish.isEmpty {
            restore(save)
        } else {
            // 라운지는 정원의 20%로 문을 연다 — 첫날부터 어느 정도 풍성하되
            // 남은 80%가 몇 달치 성장 여지로 남는다. 복원된 어항은 건드리지 않는다.
            for _ in 0..<(lounge ? max(5, maxFish / 5) : 5) { spawnAdult() }
        }
        refreshEnvNight()
        wasNight = isNight
        bump("launches")
        let initialNew = unlockSatisfied()
        if !initialNew.isEmpty { post(L10n.achievementsBatch(initialNew.count)) }
        deliverPostcards(announce: false)
    }

    func resize(cols: Int, rows: Int) {
        let colsChanged = cols != self.cols
        self.cols = cols
        self.rows = rows
        if colsChanged {
            plantWeeds()
            placeChest()
            spawnJellyfish()
            spawnCleanupCrew()
        }
        let now = self.now
        for i in fish.indices {
            if now < fish[i].enteringUntil {
                // 입장 중엔 x를 어항 안으로 당기지 않는다 — 연출이 끊긴다.
                // 다만 창이 크게 줄면 오른쪽 입장자가 수십 칸 밖에 남으므로
                // 새 가장자리까지는 끌어온다. y 클램프는 반드시 유지해야 한다
                // (밴드 밖이면 drawFish가 건너뛰어 통째로 안 보인다).
                fish[i].x = min(fish[i].x, Double(cols + 2))
                clampY(&fish[i])
            } else {
                clampToTank(&fish[i])
            }
        }
        food.removeAll { $0.x >= Double(cols - 1) }
        bubbles.removeAll { $0.x >= Double(cols - 1) }
    }

    // MARK: - Persistence

    private func restore(_ save: SaveState) {
        let now = self.now
        tankBornAt = save.tankBornAt
        lighting = Lighting(rawValue: save.lighting) ?? .auto
        season = Season(rawValue: save.season ?? "") ?? .auto
        visitorSeen = save.visitorSeen ?? [:]
        focusDone = save.focusDone ?? 0
        commitRewards = save.commitRewards ?? 0
        stats = save.stats ?? [:]
        unlocked = Set(save.unlockedAchievements ?? [])
        travelers = save.travelers ?? []
        mailbox = save.mailbox ?? []

        // Reserve saved names first so generated names can't collide with them
        for state in save.fish {
            if let name = state.name { usedNames.insert(name) }
        }
        for state in save.fish {
            fish.append(makeFish(from: state))
        }

        // Births that happened while the tank was away (at most 3 per absence)
        let maxOfflineBirths = 3
        var away = max(0, Date().timeIntervalSince1970 - save.savedAt)
        var remaining = max(1, save.breedRemaining)
        var bornAges: [Double] = []
        while away >= remaining {
            away -= remaining
            remaining = Double.random(in: breedInterval)
            if bornAges.count < maxOfflineBirths, fish.count + bornAges.count < maxFish {
                bornAges.append(away) // seconds this fish has already lived
            }
        }
        // breedRemaining은 세이브에 남으므로 모드를 바꿔 열면 남은 시간이 현재 모드의
        // 범위를 벗어난다. 라운지 세이브를 일반 모드로 열면 3일간 번식이 멈추는데,
        // 오너가 --lounge를 테스트하고 끄면 바로 겪는 함정이다. 상한으로만 자른다.
        //
        // 반대 방향(일반 세이브 → 라운지)은 일부러 손대지 않는다. 첫 아기가 25분 만에
        // 나오고 그 뒤로 2~3일 주기가 되는데, 어항을 전시용으로 옮겨온 첫날 한 번뿐이라
        // 무해하다. "짧으면 새로 뽑기"로 처리하면 라운지 카운트다운이 막바지(마지막
        // 25분)일 때 재시작이 걸리면 2~3일이 통째로 리셋된다 — 정전 한 번에 전시의
        // 성장이 조용히 날아가는 쪽이 훨씬 나쁘다.
        nextBreed = now + max(0, min(remaining - away, breedInterval.upperBound))

        for age in bornAges {
            if age >= 45 {
                spawnAdult() // already grew up while away
                bump("born")
            } else if let parent = fish.randomElement() {
                spawnBaby(near: parent)
            }
        }

        if bornAges.isEmpty {
            post(L10n.welcomeBack(count: fish.count))
        } else {
            post(L10n.offlineBirths(bornAges.count, total: fish.count))
        }
    }

    func saveState() -> SaveState {
        let now = self.now
        return SaveState(
            savedAt: Date().timeIntervalSince1970,
            tankBornAt: tankBornAt,
            breedRemaining: max(0, nextBreed - now),
            lighting: lighting.rawValue,
            fish: fish.map { f in
                FishState(species: f.species,
                          color: f.color,
                          speed: f.speed,
                          eaten: f.eaten,
                          growRemaining: f.growAt.map { max(0, $0 - now) },
                          name: f.name,
                          bornAt: f.bornAtEpoch,
                          id: f.id,
                          origin: f.origin.isEmpty ? nil : f.origin,
                          morph: f.morph == .normal ? nil : f.morph.rawValue,
                          personality: f.personality.rawValue)
            },
            visitorSeen: visitorSeen,
            focusDone: focusDone,
            tankFull: fish.count >= maxFish,
            commitRewards: commitRewards,
            stats: stats,
            unlockedAchievements: Array(unlocked),
            travelers: travelers.isEmpty ? nil : travelers,
            mailbox: mailbox.isEmpty ? nil : mailbox,
            season: season.rawValue)
    }

    func writeSave() {
        SaveStore.write(saveState())
    }

    // MARK: - Lighting

    func setLighting(_ mode: Lighting) {
        lighting = mode
        refreshEnvNight()
    }

    func toggleLighting() {
        switch lighting {
        case .auto: lighting = .night
        case .night: lighting = .day
        case .day: lighting = .auto
        }
        refreshEnvNight()
        switch lighting {
        case .auto: post(L10n.lightingAuto(isNight: isNight))
        case .night: post(L10n.lightingNight)
        case .day: post(L10n.lightingDay)
        }
    }

    private func refreshEnvNight() {
        let hour = Calendar.current.component(.hour, from: Date())
        let nightHours = hour >= 19 || hour < 7
        let dark = terminalDark ?? World.systemPrefersDark()
        envNight = dark || nightHours
    }

    private static func systemPrefersDark() -> Bool {
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

    // MARK: - Season (계절)

    func setSeason(_ mode: Season) {
        season = mode
    }

    func toggleSeason() {
        switch season {
        case .auto: season = .summer
        case .summer: season = .off
        case .off: season = .auto
        }
        switch season {
        case .auto: post(L10n.seasonAuto(isSummer: isSummer))
        case .summer: post(L10n.seasonSummer)
        case .off: post(L10n.seasonOff)
        }
    }

    // MARK: - Spawning

    private func plantWeeds() {
        weeds = []
        guard cols > 12 else { return }
        var x = Int.random(in: 3...6)
        while x < cols - 3 {
            let maxHeight = max(2, min(6, rows / 4))
            weeds.append(Weed(x: x,
                              height: Int.random(in: 2...maxHeight),
                              phase: Double.random(in: 0...(2 * .pi))))
            x += Int.random(in: 5...11)
        }
    }

    private func placeChest() {
        guard cols >= 44, sandRow - 2 >= swimMinRow else {
            chestX = nil
            return
        }
        chestX = Int.random(in: 4...(cols - 12))
        chestNextOpen = now + Double.random(in: 5...12)
        chestOpenUntil = 0
    }

    private func spawnJellyfish() {
        jellyfish = []
        let count = cols >= 70 ? 2 : (cols >= 40 ? 1 : 0)
        for _ in 0..<count {
            jellyfish.append(Jellyfish(
                x: Double.random(in: 2...Double(max(3, cols - 8))),
                y: Double.random(in: Double(swimMinRow)...Double(max(swimMinRow, swimMaxRow - 1))),
                phase: Double.random(in: 0...(2 * .pi)),
                driftSeed: Double.random(in: 0...(2 * .pi))))
        }
    }

    private func spawnCleanupCrew() {
        snails = cols >= 40
            ? [Snail(x: Double.random(in: 3...Double(cols - 4)), dir: Bool.random() ? 1 : -1)]
            : []
        crabs = cols >= 50
            ? [Crab(x: Double.random(in: 2...Double(cols - 10)), dir: Bool.random() ? 1 : -1)]
            : []
    }

    private func nextName() -> String {
        if let name = L10n.fishNames.shuffled().first(where: { !usedNames.contains($0) }) {
            usedNames.insert(name)
            return name
        }
        var suffix = 2
        while true {
            let name = L10n.fishNames.randomElement()! + "\(suffix)"
            if !usedNames.contains(name) {
                usedNames.insert(name)
                return name
            }
            suffix += 1
        }
    }

    private func spawnAdult() {
        let species = Int.random(in: 1..<allSpecies.count)
        var f = Fish(x: Double.random(in: 2...Double(max(3, cols - 10))),
                     y: Double.random(in: Double(swimMinRow)...Double(max(swimMinRow, swimMaxRow))),
                     dir: Bool.random() ? 1 : -1,
                     speed: Double.random(in: allSpecies[species].speed),
                     species: species,
                     color: fishPalette.randomElement()!)
        f.name = nextName()
        f.bornAtEpoch = Date().timeIntervalSince1970
        f.personality = Personality.allCases.randomElement()!
        clampToTank(&f)
        fish.append(f)
    }

    /// FishState → Fish 복원 (restore와 입양이 공유)
    /// - Parameter entering: true면 어항 밖에서 헤엄쳐 들어오는 연출로 등장한다.
    ///   복원은 반드시 false여야 한다 — 껐다 켤 때마다 전원이 입장 행진을 하면
    ///   "어항을 다시 연다"가 아니라 "어항을 새로 만든다"가 되어버린다.
    private func makeFish(from state: FishState, entering: Bool = false) -> Fish {
        let species = min(max(0, state.species), allSpecies.count - 1)
        var f = Fish(x: Double.random(in: 2...Double(max(3, cols - 10))),
                     y: Double.random(in: Double(swimMinRow)...Double(max(swimMinRow, swimMaxRow))),
                     dir: Bool.random() ? 1 : -1,
                     speed: state.speed,
                     species: species,
                     color: state.color)
        f.eaten = state.eaten
        f.growAt = state.growRemaining.map { now + $0 }
        f.name = state.name ?? nextName()
        f.bornAtEpoch = state.bornAt ?? tankBornAt
        if let id = state.id, !id.isEmpty { f.id = id }
        f.origin = state.origin ?? []
        f.morph = Morph(rawValue: state.morph ?? 0) ?? .normal
        f.personality = Personality(rawValue: state.personality ?? Int.random(in: 0..<Personality.allCases.count)) ?? .shy
        usedNames.insert(f.name)
        if entering {
            // 방향을 먼저 정하고 x를 거기서 유도한다. 둘을 독립적으로 굴리면
            // 절반이 왼쪽 밖에서 왼쪽을 보고 태어나 영영 안 들어온다.
            f.dir = Bool.random() ? 1 : -1
            f.x = f.dir > 0 ? -Double(f.art.count) - 1 : Double(cols + 2)
            f.enteringUntil = now + 10
            clampY(&f)          // x는 일부러 안 자른다
        } else {
            clampToTank(&f)     // 기존 동작 그대로
        }
        return f
    }

    @discardableResult
    private func spawnBaby(near parent: Fish) -> String {
        var baby = Fish(x: parent.x,
                        y: parent.y,
                        dir: Bool.random() ? 1 : -1,
                        speed: Double.random(in: 0.2...0.45),
                        species: 0,
                        color: parent.color,
                        growAt: now + Double.random(in: 30...55))
        baby.name = nextName()
        baby.bornAtEpoch = Date().timeIntervalSince1970
        baby.personality = Double.random(in: 0...1) < 0.2
            ? Personality.allCases.randomElement()! : parent.personality
        clampToTank(&baby)
        fish.append(baby)
        bump("born")
        return baby.name
    }

    private func clampToTank(_ f: inout Fish) {
        let maxX = Double(max(2, cols - 2 - f.art.count))
        f.x = min(max(1, f.x), maxX)
        clampY(&f)
    }

    /// y만 어항 안으로. 입장 중인 물고기는 x가 밖이어도 되지만 y는 반드시
    /// 유영 밴드 안이어야 한다 — drawFish가 밴드 밖 행을 통째로 건너뛰어서
    /// 물고기가 통째로 안 보이게 된다.
    private func clampY(_ f: inout Fish) {
        f.y = min(max(Double(swimMinRow), f.y), Double(max(swimMinRow, swimMaxRow)))
    }

    // MARK: - Input

    func feed() {
        guard food.count < 60 else { return }
        sprinkleFood(Int.random(in: 4...7))
        // 여름 한정: 손으로 준 먹이에만 수박 한 조각이 섞인다
        // (커밋 보상·집중 완료 대잔치는 sprinkleFood를 직접 부르므로 해당 없음)
        // 동시에 한 조각만 — 3칸 글리프가 서로 겹쳐 깨지는 걸 구조적으로 차단
        let melon = isSummer && cols > 10
            && !food.contains(where: { $0.kind == .watermelon })
            && Double.random(in: 0...1) < 0.25
        if melon {
            food.append(Food(x: Double.random(in: 3...Double(cols - 4)),
                             y: Double(surfaceRow + 1),
                             vy: Double.random(in: 0.08...0.16), // 수박은 천천히 가라앉는다
                             restingSince: nil,
                             kind: .watermelon))
            bump("fed")
        }
        bump("feedActions")
        post(melon ? L10n.watermelonDropped : L10n.foodSprinkled)
    }

    private func sprinkleFood(_ count: Int) {
        guard cols > 8 else { return }
        bump("fed", count)
        for _ in 0..<count {
            food.append(Food(x: Double.random(in: 2...Double(cols - 3)),
                             y: Double(surfaceRow + 1),
                             vy: Double.random(in: 0.12...0.28),
                             restingSince: nil))
        }
    }

    // MARK: - Focus (pomodoro)

    func startFocus(minutes: Int) {
        let clamped = min(180, max(1, minutes))
        focusUntil = now + Double(clamped) * 60
        post(L10n.focusStarted(clamped))
    }

    func toggleFocus() {
        if focusUntil != nil {
            focusUntil = nil
            post(L10n.focusCancelled)
        } else {
            startFocus(minutes: 25)
        }
    }

    /// git 커밋 보상: 실행 중이면 즉시 먹이가 쏟아지고, 남는 몫은 번식 가속으로
    private func applyCommitReward(_ commits: Int) {
        commitRewards += commits
        sprinkleFood(min(12, commits * 5))
        if !lounge { nextBreed -= Double(commits) * 30 } // 먹이만, 성장 가속은 라운지 제외
        post(L10n.rewardArrived(commits))
        writeSave()
    }

    private func completeFocus(_ now: Double) {
        focusUntil = nil
        focusDone += 1
        sprinkleFood(Int.random(in: 10...14)) // feast time
        nextBreed -= 180
        for _ in 0..<10 {
            bubbles.append(Bubble(x: Double.random(in: 2...Double(max(3, cols - 3))),
                                  y: Double(sandRow - 1),
                                  phase: Double.random(in: 0...(2 * .pi)),
                                  speed: Double.random(in: 0.2...0.4)))
        }
        Sound.playChime()
        post(L10n.focusComplete(focusDone))
        if !ephemeral { writeSave() }
    }

    private func post(_ text: String) {
        message = text
        messageUntil = now + 4
    }

    func toggleRoster() {
        rosterOpen.toggle()
        if rosterOpen { mailboxOpen = false; sponsorOpen = false }
    }

    func toggleMailbox() {
        mailboxOpen.toggle()
        if mailboxOpen {
            rosterOpen = false
            sponsorOpen = false
            for i in mailbox.indices { mailbox[i].read = true } // 열면 읽음 처리
        }
    }

    func toggleSponsor() {
        sponsorOpen.toggle()
        if sponsorOpen { rosterOpen = false; mailboxOpen = false }
    }

    func openSponsor() {
        guard sponsorOpen else { return }
        Support.openInBrowser()
        post(L10n.sponsorOpened)
    }

    func toggleMusic() {
        let wasPlaying = MusicPlayer.shared.isPlaying
        post(MusicPlayer.shared.toggle())
        if !wasPlaying && MusicPlayer.shared.isPlaying { bump("music") }
    }

    /// Live food: a school of brine shrimp that actively flees the fish.
    func feedLive() {
        guard cols > 12, shrimp.count < 30 else { return }
        let now = self.now
        let originX = Double.random(in: 4...Double(cols - 5))
        let batch = Int.random(in: 6...10)
        bump("shrimp", batch)
        for _ in 0..<batch {
            shrimp.append(Shrimp(x: originX + Double.random(in: -2...2),
                                 y: Double(surfaceRow) + 1 + Double.random(in: 0...1.5),
                                 vx: Double.random(in: -0.3...0.3),
                                 vy: Double.random(in: 0.05...0.2),
                                 bornAt: now))
        }
        post(L10n.shrimpReleased)
    }

    /// Handles a mouse click at 0-based grid coordinates.
    func touch(col: Int, row: Int) {
        if rosterOpen || mailboxOpen || sponsorOpen {
            rosterOpen = false
            mailboxOpen = false
            sponsorOpen = false
            return
        }
        let now = self.now

        for i in fish.indices.reversed() {
            let f = fish[i]
            // 입장 중엔 못 만진다 — 아래에서 dir을 뒤집는데 입장 분기가 그 dir로
            // 움직인다. 탭당한 입장자가 그대로 되돌아 나가버린다. 라운지의
            // 키오스크 가드는 키만 막고 클릭은 통과시키므로, 지나가던 사람이
            // 유리를 두드리는 라운지가 바로 이게 터지는 곳이다.
            if now < f.enteringUntil { continue }
            let r = Int(f.y.rounded())
            let c0 = Int(f.x.rounded())
            guard abs(r - row) <= 1, col >= c0 - 1, col <= c0 + f.art.count else { continue }

            post(L10n.touchedBy(f.name, personality: f.personality, mood: mood(f)))
            bump("touch"); if isNight { bump("touchNight") }
            Sound.playTouch()
            fish[i].panicUntil = now + traits(f.personality).panic
            fish[i].dir = Double(c0 + f.art.count / 2) >= Double(col) ? 1 : -1
            fish[i].vy = Double.random(in: -0.25...0.25)
            for _ in 0..<2 {
                bubbles.append(Bubble(x: f.mouthX, y: f.y - 0.5,
                                      phase: Double.random(in: 0...(2 * .pi)),
                                      speed: Double.random(in: 0.2...0.35)))
            }
            return
        }

        // Tapping the glass: just a startled little bubble
        if row >= swimMinRow, row <= swimMaxRow, col > 0, col < cols - 1 {
            bubbles.append(Bubble(x: Double(col), y: Double(row),
                                  phase: Double.random(in: 0...(2 * .pi)),
                                  speed: Double.random(in: 0.15...0.3)))
        }
    }

    // MARK: - Simulation

    func update() {
        tick += 1
        let now = self.now

        if now >= nextEnvCheck {
            nextEnvCheck = now + 60
            refreshEnvNight()
        }
        if !ephemeral, now >= nextAutosave {
            nextAutosave = now + 60
            writeSave()
        }
        if let title = MusicPlayer.shared.pollNewTitle() {
            post(L10n.nowPlaying(title))
        }
        if let deadline = focusUntil, now >= deadline {
            completeFocus(now)
        }
        if !ephemeral, now >= nextInboxCheck {
            nextInboxCheck = now + 5
            let commits = RewardInbox.consume()
            if commits > 0 { applyCommitReward(commits) }
            ingestAdoptions()
            processReleases()
        }
        if isNight && !wasNight { bump("nights") }
        wasNight = isNight
        if now >= nextAchvCheck {
            nextAchvCheck = now + 1
            for a in unlockSatisfied() {
                post(L10n.achievementUnlocked(a.name))
                Sound.playChime()
            }
        }
        if !ephemeral, now >= nextPostcardCheck {
            nextPostcardCheck = now + 7
            deliverPostcards(announce: true)
        }
        // 무인 전시라 아무도 f를 눌러주지 않는다 — 어항이 스스로 먹이를 뿌린다.
        // feed()가 아니라 sprinkleFood()를 부르는 이유: feed()는 feedActions 업적을
        // 올리고(자동 먹이가 업적을 채우면 무의미해진다) 여름엔 수박을 25% 굴린다.
        // 커밋 보상·집중 완료 대잔치도 같은 이유로 sprinkleFood를 직접 부른다.
        if lounge, now >= nextAutoFeedAt {
            nextAutoFeedAt = now + Double.random(in: 90...180) * loungeScale
            if food.count < 20 { sprinkleFood(Int.random(in: 3...5)) }
        }
        // QR은 상시 노출이 아니라 잠깐씩 뜬다 — 전시의 본질은 수조고, 오히려
        // 떴다 사라지는 쪽이 시선을 끈다. (loungeScale은 안 쓴다. 1/1200이면
        // 압축 모드에서 한 프레임도 안 보인다.)
        if lounge, now >= nextQRAt {
            nextQRAt = now + (loungeFast ? 20 : 120)
            qrShownUntil = now + (loungeFast ? 8 : 20)
        }

        updateFish(now)
        updateFood(now)
        updateShrimp(now)
        updateBubbles(now)
        updateJellyfish(now)
        updateChest(now)
        updateCleanupCrew(now)
        updateVisitor(now)

        // The tank slowly fills up on its own; feeding just speeds it along.
        // (라운지는 예외 — 먹이가 nextBreed를 못 깎는다. updateFish 참고.)
        if now >= nextBreed {
            nextBreed = now + Double.random(in: breedInterval)
            if fish.count < maxFish, let parent = fish.randomElement() {
                let name = spawnBaby(near: parent)
                post(L10n.babyBorn(name, count: fish.count))
            } else if !lounge, fish.count >= maxFish {
                // 라운지에서 이 분기를 건너뛰는 이유: 진화는 아래 nextEvolveAt이
                // 담당하고, departOnJourney는 막아야 한다 — 동료가 분양한 물고기가
                // 어느 날 조용히 사라지면 "모두의 수조"가 성립하지 않는다.
                // tankFull 메시지도 무인 전시에는 알릴 사람이 없다.
                let r = Double.random(in: 0...1)
                if r < 0.35, let idx = oldestNormalAdultIndex() {
                    evolveFish(idx)
                } else if r < 0.75, let idx = oldestAdultIndex() {
                    departOnJourney(idx)
                } else {
                    post(L10n.tankFull(maxFish))
                }
            }
        }

        // 진화를 번식 타이머에서 분리한다. 원래 evolveFish는 "어항이 가득 찼을 때"만
        // 발동하는데, 라운지는 정원 120에 번식이 2~3일이라 몇 달간 차지 않는다 —
        // 그대로 두면 희귀 모프가 전시 내내 한 번도 안 나온다.
        if lounge, now >= nextEvolveAt {
            nextEvolveAt = now + Double.random(in: 21_600...43_200) * loungeScale
            if let idx = oldestNormalAdultIndex() { evolveFish(idx) }
        }
    }

    private func updateFish(_ now: Double) {
        for i in fish.indices {
            var f = fish[i]

            // 입장 연출 — 어항 밖에서 곧장 헤엄쳐 들어온다. 이 3초 남짓 동안은
            // 먹이·새우·성장·거품·가장자리 반사를 전부 건너뛴다.
            //
            // 아래 분기를 공유하지 않고 전용 분기를 파는 이유는 밤 분기에 있다 —
            // 0.3% 확률로 dir을 뒤집는데, 입장 40여 틱 동안 한 번만 뒤집혀도
            // 물고기가 밖으로 되돌아간다. 그리고 라운지는 밤새 돈다.
            if now < f.enteringUntil {
                // 느린 종(아귀 0.08, 갈치 0.12)이 제 속도로 들어오면 10초가 걸려
                // 5초 페이싱 간격을 넘긴다 — 입장 속도에만 바닥을 둔다.
                // 들어온 뒤엔 제 속도로 돌아간다.
                f.x += f.dir * max(f.speed, 0.35)
                let maxX = Double(max(2, cols - 2 - f.art.count))
                // 도착 즉시 해제한다. 안 지우면 이미 들어온 뒤에도 남은 시간만큼
                // 가장자리 반사가 면제돼 반대편 벽을 뚫고 나간다.
                if f.x >= 1, f.x <= maxX { f.enteringUntil = 0 }
                fish[i] = f
                continue
            }

            let t = traits(f.personality)

            if now < f.panicUntil {
                // Touched! Dart away from the finger
                f.x += f.dir * f.speed * 3.5
            } else if let target = nearestPrey(for: f) {
                let dx = target.x - f.mouthX
                if abs(dx) > 1 { f.dir = dx > 0 ? 1 : -1 }
                f.vy = max(-0.3, min(0.3, (target.y - f.y) * 0.12))
                f.x += f.dir * f.speed * t.chaseMult
            } else if isNight {
                // Sleepy drift: slow, near the bottom, rarely turning
                if Double.random(in: 0...1) < 0.003 { f.dir = -f.dir }
                if f.y < Double(swimMaxRow - 2) { f.vy += 0.003 }
                f.x += f.dir * f.speed * 0.25
            } else {
                if Double.random(in: 0...1) < t.turnProb { f.dir = -f.dir }
                if Double.random(in: 0...1) < t.jitterProb { f.vy = Double.random(in: -t.jitter...t.jitter) }
                f.vy += t.vyBias
                f.x += f.dir * f.speed * t.moveMult
            }

            f.y += f.vy
            f.vy *= 0.96

            let maxX = Double(max(2, cols - 2 - f.art.count))
            if f.x <= 1 { f.x = 1; f.dir = 1 }
            if f.x >= maxX { f.x = maxX; f.dir = -1 }
            if f.y <= Double(swimMinRow) { f.y = Double(swimMinRow); f.vy = abs(f.vy) }
            if f.y >= Double(swimMaxRow) { f.y = Double(swimMaxRow); f.vy = -abs(f.vy) }

            for fi in food.indices.reversed() {
                if abs(food[fi].x - f.mouthX) < 2.0, abs(food[fi].y - f.y) < 1.3 {
                    let melon = food[fi].kind == .watermelon
                    food.remove(at: fi)
                    f.eaten += 1
                    bump("meals")
                    if melon { bump("watermelon") }
                    // 라운지에선 먹이가 성장을 못 당긴다 — 자동 먹이가 90~180초마다
                    // 3~5알을 뿌리므로 다 먹히면 135초당 -90~150초, 시간이 두 배로
                    // 흘러 "2~3일"이 허구가 된다. 거기에 행인이 f를 연타하면 더 빨라져
                    // 예측 자체가 불가능해진다. 라운지에서 먹이는 연출이고 성장은 시계다.
                    if !lounge { nextBreed -= melon ? 45 : 30 } // 수박은 여름 보양식
                    bubbles.append(Bubble(x: f.mouthX, y: f.y - 0.5,
                                          phase: Double.random(in: 0...(2 * .pi)),
                                          speed: Double.random(in: 0.2...0.35)))
                    break
                }
            }

            for si in shrimp.indices.reversed() {
                if abs(shrimp[si].x - f.mouthX) < 1.5, abs(shrimp[si].y - f.y) < 1.2 {
                    shrimp.remove(at: si)
                    f.eaten += 1
                    bump("meals"); bump("shrimpEaten")
                    if !lounge { nextBreed -= 45 } // live food is extra nutritious
                    bubbles.append(Bubble(x: f.mouthX, y: f.y - 0.5,
                                          phase: Double.random(in: 0...(2 * .pi)),
                                          speed: Double.random(in: 0.2...0.35)))
                    break
                }
            }

            if Double.random(in: 0...1) < 0.008 {
                bubbles.append(Bubble(x: f.mouthX, y: f.y,
                                      phase: Double.random(in: 0...(2 * .pi)),
                                      speed: Double.random(in: 0.15...0.3)))
            }

            if let growAt = f.growAt, now >= growAt {
                f.species = Int.random(in: 1..<allSpecies.count)
                f.speed = Double.random(in: allSpecies[f.species].speed)
                f.growAt = nil
                clampToTank(&f)
                if f.morph == .normal, Double.random(in: 0...1) < 0.02 {
                    f.morph = rareMorphs.randomElement()!
                    bump("morphs")
                    post(L10n.grewRare(f.name, L10n.morphName(f.morph)))
                }
            }

            fish[i] = f
        }
    }

    /// 성격별 이동/반응 계수
    private func traits(_ p: Personality)
        -> (preyRange: Double, chaseMult: Double, moveMult: Double,
            turnProb: Double, jitterProb: Double, jitter: Double, vyBias: Double, panic: Double) {
        switch p {
        case .shy:     return (14, 1.4, 1.0,  0.02,  0.05, 0.10,  0.004, 3.0)
        case .greedy:  return (42, 2.3, 1.0,  0.01,  0.05, 0.10,  0.0,   1.5)
        case .playful: return (28, 1.8, 1.1,  0.035, 0.12, 0.15,  0.0,   1.2)
        case .lazy:    return (12, 1.4, 0.6,  0.004, 0.02, 0.06,  0.005, 1.5)
        case .bold:    return (28, 1.9, 1.15, 0.01,  0.05, 0.10, -0.004, 0.6)
        }
    }

    /// 현재 상황에서 파생되는 기분 (저장 없음) — 터치 반응에 사용
    private func mood(_ f: Fish) -> Mood {
        if isNight { return .sleepy }
        if nearestPrey(for: f) != nil { return .eating }
        return .idle
    }

    private func nearestPrey(for f: Fish) -> (x: Double, y: Double)? {
        let range = traits(f.personality).preyRange
        var best: (x: Double, y: Double)?
        var bestScore = Double.infinity
        for pellet in food where abs(pellet.x - f.x) < range {
            let score = pow(pellet.x - f.x, 2) + pow((pellet.y - f.y) * 2, 2)
            if score < bestScore {
                bestScore = score
                best = (pellet.x, pellet.y)
            }
        }
        for s in shrimp where abs(s.x - f.x) < range {
            // Live prey is preferred over sinking pellets
            let score = (pow(s.x - f.x, 2) + pow((s.y - f.y) * 2, 2)) * 0.8
            if score < bestScore {
                bestScore = score
                best = (s.x, s.y)
            }
        }
        return best
    }

    private func updateShrimp(_ now: Double) {
        for i in shrimp.indices {
            var s = shrimp[i]

            // Erratic wiggle
            if Double.random(in: 0...1) < 0.15 {
                s.vx += Double.random(in: -0.15...0.15)
                s.vy += Double.random(in: -0.1...0.1)
            }

            // Flee the nearest fish mouth
            var threat: (dx: Double, dy: Double)?
            var threatDist = 49.0 // within 7 columns
            for f in fish {
                let dx = s.x - f.mouthX
                let dy = s.y - f.y
                let dist = dx * dx + dy * dy * 4
                if dist < threatDist {
                    threatDist = dist
                    threat = (dx, dy)
                }
            }
            if let threat {
                s.vx += (threat.dx >= 0 ? 1 : -1) * 0.08
                s.vy += (threat.dy >= 0 ? 1 : -1) * 0.04
            }

            s.vx = max(-0.5, min(0.5, s.vx))
            s.vy = max(-0.3, min(0.3, s.vy))
            s.x += s.vx
            s.y += s.vy

            if s.x <= 1.5 { s.x = 1.5; s.vx = abs(s.vx) }
            if s.x >= Double(cols - 3) { s.x = Double(cols - 3); s.vx = -abs(s.vx) }
            if s.y <= Double(swimMinRow) { s.y = Double(swimMinRow); s.vy = abs(s.vy) }
            if s.y >= Double(swimMaxRow) { s.y = Double(swimMaxRow); s.vy = -abs(s.vy) }

            shrimp[i] = s
        }
        // Survivors eventually hide in the sand
        shrimp.removeAll { now - $0.bornAt > 50 }
    }

    private func updateFood(_ now: Double) {
        for i in food.indices {
            if food[i].y < Double(sandRow) {
                food[i].y = min(Double(sandRow), food[i].y + food[i].vy)
            } else if food[i].restingSince == nil {
                food[i].restingSince = now
            }
        }
        food.removeAll { resting in
            if let since = resting.restingSince { return now - since > 25 }
            return false
        }
    }

    private func updateBubbles(_ now: Double) {
        for i in bubbles.indices {
            bubbles[i].y -= bubbles[i].speed
            bubbles[i].x += sin(now * 3 + bubbles[i].phase) * 0.12
        }
        bubbles.removeAll { $0.y <= Double(surfaceRow) + 0.5 || $0.x < 1 || $0.x >= Double(cols - 1) }

        if Double.random(in: 0...1) < 0.15, cols > 8 {
            let x = weeds.randomElement().map { Double($0.x) + Double.random(in: -1...1) }
                ?? Double.random(in: 2...Double(cols - 3))
            bubbles.append(Bubble(x: min(max(2, x), Double(cols - 3)),
                                  y: Double(sandRow - 1),
                                  phase: Double.random(in: 0...(2 * .pi)),
                                  speed: Double.random(in: 0.15...0.35)))
        }
    }

    private func updateJellyfish(_ now: Double) {
        for i in jellyfish.indices {
            var j = jellyfish[i]
            j.vy += j.isContracted(at: now) ? -0.018 : 0.010
            j.vy = max(-0.15, min(0.1, j.vy))
            j.y += j.vy
            j.x += sin(now * 0.4 + j.driftSeed) * 0.06

            let minY = Double(swimMinRow)
            let maxY = Double(max(swimMinRow, swimMaxRow - 1)) // two rows tall
            if j.y < minY { j.y = minY; j.vy = 0.05 }
            if j.y > maxY { j.y = maxY; j.vy = -0.05 }
            j.x = min(max(1, j.x), Double(max(1, cols - 7)))
            jellyfish[i] = j
        }
    }

    private func updateChest(_ now: Double) {
        guard let cx = chestX else { return }

        if now >= chestOpenUntil, now >= chestNextOpen {
            chestOpenUntil = now + Double.random(in: 2...3.5)
            chestNextOpen = now + Double.random(in: 10...18)
            bump("chest")
            // The lid popping open startles fish loitering near the bottom.
            let center = Double(cx) + 3
            for i in fish.indices where abs(fish[i].x - center) < 12
                && fish[i].y > Double(swimMaxRow - 6) {
                fish[i].dir = fish[i].x < center ? -1 : 1
                fish[i].vy = -0.3
            }
        }

        if now < chestOpenUntil, Double.random(in: 0...1) < 0.5 {
            bubbles.append(Bubble(x: Double(cx) + Double.random(in: 1.5...4.5),
                                  y: Double(sandRow - 3),
                                  phase: Double.random(in: 0...(2 * .pi)),
                                  speed: Double.random(in: 0.2...0.4)))
        }
    }

    private func updateCleanupCrew(_ now: Double) {
        // Snail: a slow, purposeful janitor heading for sunken food
        for i in snails.indices {
            var s = snails[i]
            defer { snails[i] = s }
            guard now >= s.pauseUntil else { continue }

            let target = food
                .filter { $0.restingSince != nil }
                .min(by: { abs($0.x - s.x) < abs($1.x - s.x) })
            if let target {
                if abs(target.x - s.x) > 0.8 { s.dir = target.x > s.x ? 1 : -1 }
            } else {
                if Double.random(in: 0...1) < 0.005 { s.dir = -s.dir }
                if Double.random(in: 0...1) < 0.004 { s.pauseUntil = now + Double.random(in: 1...4) }
            }
            s.x += s.dir * 0.05
            s.x = min(max(1.5, s.x), Double(cols - 3))

            for fi in food.indices.reversed()
            where food[fi].restingSince != nil && abs(food[fi].x - s.x) < 1.2 {
                food.remove(at: fi)
                bubbles.append(Bubble(x: s.x, y: Double(sandRow - 2),
                                      phase: Double.random(in: 0...(2 * .pi)),
                                      speed: Double.random(in: 0.15...0.25)))
            }
        }

        // Crab: sideways scuttle, snack breaks, occasional claw waving
        for i in crabs.indices {
            var c = crabs[i]
            defer { crabs[i] = c }

            if now >= c.modeUntil {
                switch c.mode {
                case .walking:
                    if Double.random(in: 0...1) < 0.5 {
                        c.mode = .pausing
                        c.modeUntil = now + Double.random(in: 1...3)
                    } else {
                        c.mode = .waving
                        c.modeUntil = now + Double.random(in: 1.5...3)
                    }
                case .pausing, .waving:
                    c.mode = .walking
                    c.modeUntil = now + Double.random(in: 3...8)
                    if Bool.random() { c.dir = -c.dir }
                }
            }

            guard c.mode == .walking else { continue }
            c.x += c.dir * 0.15
            let maxX = Double(max(2, cols - 9)) // art is 7 wide
            if c.x <= 1.5 { c.x = 1.5; c.dir = 1 }
            if c.x >= maxX { c.x = maxX; c.dir = -1 }

            for fi in food.indices.reversed()
            where food[fi].restingSince != nil && abs(food[fi].x - (c.x + 3)) < 2 {
                food.remove(at: fi)
            }
        }
    }

    // MARK: - Rare visitors

    private func updateVisitor(_ now: Double) {
        if let cloud = inkCloud, now - cloud.bornAt > 4 { inkCloud = nil }

        if visitor == nil, now >= nextVisitorAt, cols >= 50, rows >= 16 {
            spawnVisitor(now)
        }
        guard var v = visitor else { return }

        switch v.kind {
        case .whale, .turtle, .sunfish:
            let speed: Double
            switch v.kind {
            case .whale: speed = 0.28
            case .turtle: speed = 0.18
            case .sunfish: speed = 0.13 // 개복치는 물살에 떠밀리듯 느긋하게
            case .octopus: speed = 0
            }
            v.x += v.dir * speed
            if v.kind == .turtle { v.y += sin(now * 1.2) * 0.03 }
            if v.kind == .sunfish { v.y += sin(now * 0.5) * 0.02 } // 흐느적 상하 표류
            let width = Double(visitorArt(v).map(\.count).max() ?? 20)
            if (v.dir > 0 && v.x > Double(cols)) || (v.dir < 0 && v.x < -width) {
                visitor = nil
                scheduleNextVisitor(now)
            } else {
                visitor = v
            }
        case .octopus:
            if let departAt = v.departAt, now >= departAt {
                inkCloud = (v.x + 4, v.y + 1, now)
                visitor = nil
                scheduleNextVisitor(now)
                post(L10n.octopusVanished)
            } else {
                v.y += sin(now * 2) * 0.02
                visitor = v
            }
        }
    }

    private func spawnVisitor(_ now: Double) {
        // 개복치는 여름에만 합류 (AQUARIUM_VISITOR는 계절 무시 — 테스트용 탈출구)
        let pool = VisitorKind.allCases.filter { $0 != .sunfish || isSummer }
        var kind = VisitorKind(rawValue: debugVisitor ?? "") ?? pool.randomElement()!
        if kind == .whale, swimMaxRow - swimMinRow < 8 { kind = .turtle }

        let dir: Double = Bool.random() ? 1 : -1
        switch kind {
        case .whale:
            visitor = Visitor(kind: kind,
                              x: dir > 0 ? -24 : Double(cols + 2),
                              y: Double(swimMinRow + 1),
                              dir: dir, departAt: nil)
            post(L10n.whalePassing)
        case .turtle:
            visitor = Visitor(kind: kind,
                              x: dir > 0 ? -12 : Double(cols + 2),
                              y: Double.random(in: Double(swimMinRow + 2)...Double(max(swimMinRow + 2, swimMaxRow - 4))),
                              dir: dir, departAt: nil)
            post(L10n.turtleVisiting)
        case .octopus:
            visitor = Visitor(kind: kind,
                              x: Double.random(in: 4...Double(max(5, cols - 14))),
                              y: Double.random(in: Double(swimMinRow + 2)...Double(max(swimMinRow + 2, swimMaxRow - 5))),
                              dir: 1, departAt: now + 8)
            post(L10n.octopusAppeared)
        case .sunfish:
            visitor = Visitor(kind: kind,
                              x: dir > 0 ? -8 : Double(cols + 2),
                              y: Double.random(in: Double(swimMinRow + 1)...Double(max(swimMinRow + 1, swimMaxRow - 5))),
                              dir: dir, departAt: nil)
            post(L10n.sunfishDrifting)
        }
        visitorSeen[kind.rawValue, default: 0] += 1
    }

    private func scheduleNextVisitor(_ now: Double) {
        // 라운지는 debugVisitor와 별개의 분기다 — AQUARIUM_VISITOR는 종을 고정하므로
        // 빈도 노브로 재사용하면 전시가 한 종에 박힌다. 라운지 방문객은 무작위여야 한다.
        let interval: ClosedRange<Double>
        if debugVisitor != nil { interval = 15...25 }
        else if lounge { interval = 90...200 }
        else { interval = 240...600 }
        nextVisitorAt = now + Double.random(in: interval)
    }

    private func visitorArt(_ v: Visitor) -> [[Character]] {
        switch v.kind {
        case .whale:
            return v.dir > 0 ? whaleArtRight : whaleArtLeft
        case .turtle:
            return v.dir > 0
                ? [Array("  ______   "), Array("~(______)°>")]
                : [Array("   ______  "), Array("<°(______)~")]
        case .octopus:
            let tentacles = (tick / 4) % 2 == 0 ? " /|/|\\|\\ " : " \\|\\|/|/ "
            return [Array(" .-\"\"\"-. "), Array("( °   ° )"), Array(tentacles)]
        case .sunfish:
            return v.dir > 0 ? sunfishArtRight : sunfishArtLeft
        }
    }

    // MARK: - Wanderlust & postcards

    private func oldestAdultIndex() -> Int? {
        fish.indices
            .filter { fish[$0].growAt == nil }
            .min { fish[$0].bornAtEpoch < fish[$1].bornAtEpoch }
    }

    private func oldestNormalAdultIndex() -> Int? {
        fish.indices
            .filter { fish[$0].growAt == nil && fish[$0].morph == .normal }
            .min { fish[$0].bornAtEpoch < fish[$1].bornAtEpoch }
    }

    /// 가장 오래된 평범한 성체가 희귀 변종으로 진화 (잃지 않고 그 자리에서 변형)
    private func evolveFish(_ index: Int) {
        let morph = rareMorphs.randomElement()!
        fish[index].morph = morph
        bump("morphs")
        post(L10n.evolved(fish[index].name, L10n.morphName(morph)))
        Sound.playChime()
        writeSave()
    }

    /// 물고기가 스스로 여행을 떠남 — 자리를 비우고 나중에 엽서를 보낸다
    private func departOnJourney(_ index: Int) {
        let f = fish.remove(at: index)
        let e = nowEpoch
        travelers.append(Traveler(name: f.name,
                                  departedAt: e,
                                  nextPostcardAt: e + Double.random(in: 180...420),
                                  sent: 0))
        post(L10n.departedWander(f.name))
    }

    /// 도착 예정인 엽서를 배달. announce=false면 실행 시 밀린 엽서를 요약해 알림.
    private func deliverPostcards(announce: Bool) {
        let e = nowEpoch
        var delivered = 0
        for i in travelers.indices {
            while travelers[i].sent < 5, travelers[i].nextPostcardAt <= e {
                mailbox.append(Postcard(from: travelers[i].name,
                                        location: Int.random(in: 0..<L10n.postcardLocationCount),
                                        message: Int.random(in: 0..<L10n.postcardMessageCount),
                                        at: travelers[i].nextPostcardAt,
                                        read: false))
                travelers[i].sent += 1
                travelers[i].nextPostcardAt = e + Double.random(in: 600...1500)
                delivered += 1
            }
        }
        if mailbox.count > 50 { mailbox.removeFirst(mailbox.count - 50) }
        guard delivered > 0 else { return }
        writeSave()
        if announce, let last = mailbox.last {
            post(L10n.postcardArrived(last.from, L10n.postcardLocation(last.location)))
            Sound.playChime()
        } else if !announce {
            post(L10n.postcardsBatch(delivered))
        }
    }

    /// 입양 인박스를 받아 물고기를 어항에 추가 (정원 초과 허용 — 선물은 특별하니까)
    ///
    /// 한 번의 점검(5초)에 한 마리만 들인다. 버스트로 20개가 쏟아져도 차임이
    /// 20개 겹치지 않고, post()가 4초짜리 슬롯 하나뿐이라 마지막 한 줄만 남던
    /// 문제도 같이 사라진다. 줄지어 들어오는 게 그대로 연출이 된다.
    ///
    /// 간격은 기존 nextInboxCheck 게이트를 그대로 쓴다. 새 타이머도 env 노브도
    /// 두지 않았다 — 진짜 제약은 "페이싱 간격 > 입장 소요"(5s > 약 3s)인데,
    /// 노브를 열면 누군가 1초로 맞춰 같은 쪽에서 겹쳐 들어오게 만든다.
    private func ingestAdoptions() {
        // 페이싱 대상은 '들어온 물고기'지 '소비한 토큰'이 아니다. 중복이나
        // 손상 토큰이 앞에 쌓였다고 100초를 버릴 이유가 없다 — 거부되는
        // 토큰은 계속 넘기고 실제로 입장했을 때만 빠져나간다.
        var attempts = 0
        while attempts < 20, let token = AdoptInbox.takeFirst() {
            attempts += 1
            guard let state = Passport.decode(token) else { continue }
            if let id = state.id, fish.contains(where: { $0.id == id }) { continue } // 중복 붙여넣기 방지
            let f = makeFish(from: state, entering: true)
            fish.append(f)
            bump("adopted")
            post(L10n.adopted(f.name, from: f.origin.last))
            Sound.playChime()
            return
        }
    }

    /// 분양 아웃박스를 받아 해당 물고기를 떠나보냄
    private func processReleases() {
        for name in ReleaseOutbox.drain() {
            if let idx = fish.firstIndex(where: { $0.name == name }) {
                fish.remove(at: idx)
                bump("released")
                post(L10n.releaseDeparted(name))
            }
        }
    }

    /// 조건을 만족하지만 아직 안 잠긴 업적을 잠금 해제하고 그 목록을 반환.
    @discardableResult
    private func unlockSatisfied() -> [Achievement] {
        let merged = Achievements.mergedStats(from: saveState())
        var newly: [Achievement] = []
        for a in Achievements.all where !unlocked.contains(a.id)
            && Achievements.isUnlocked(a, stats: merged) {
            unlocked.insert(a.id)
            newly.append(a)
        }
        return newly
    }

    var achievementCount: Int { unlocked.count }

    // MARK: - Rendering

    func render() -> String {
        guard cols >= 34, rows >= 12 else {
            return ANSI.home + ANSI.clear + ANSI.fg(220)
                + L10n.enlargeTerminal + ANSI.reset
        }

        let grid = composeGrid()

        // 프레임 전체를 동기화 출력으로 감싼다 — 터미널이 중간 상태를 그리지 않는다.
        var out = ANSI.syncBegin + ANSI.home
        var lastColor: UInt8 = 0
        for (r, row) in grid.enumerated() {
            if r > 0 { out += "\r\n" }
            for cell in row {
                if cell.ch == " " {
                    out.append(" ")
                    continue
                }
                let color = cell.glow ? cell.color : dimmed(cell.color)
                if color != lastColor {
                    out += ANSI.fg(color)
                    lastColor = color
                }
                out.append(cell.ch)
            }
        }
        out += "\r\n" + statusLine(now) + "\u{1B}[K"
        if rosterOpen { out += rosterOverlay() }
        if mailboxOpen { out += mailboxOverlay() }
        if sponsorOpen { out += sponsorOverlay() }
        // 패널 셋 중 하나라도 열려 있으면 QR을 접는다 — 겹쳐 그리면 둘 다 못 읽는다.
        // (라운지 키오스크 가드가 패널 토글을 막지만 코드로도 보장한다.)
        if lounge, now < qrShownUntil, !rosterOpen, !mailboxOpen, !sponsorOpen {
            out += loungeQROverlay()
        }
        return out + ANSI.syncEnd
    }

    /// Darkens a 256-color index at night; identity during the day.
    private func dimmed(_ color: UInt8) -> UInt8 {
        guard isNight else { return color }
        switch color {
        case 16...231: // 6x6x6 color cube: scale each RGB channel down
            let idx = Int(color) - 16
            func scale(_ v: Int) -> Int { v == 0 ? 0 : max(1, Int(Double(v) * 0.55)) }
            let r = scale(idx / 36), g = scale((idx % 36) / 6), b = scale(idx % 6)
            return UInt8(16 + r * 36 + g * 6 + b)
        case 232...255: // grayscale ramp
            return UInt8(max(233, Int(color) - 8))
        default:
            return color
        }
    }

    func composeGrid() -> [[Cell]] {
        var grid = [[Cell]](repeating: [Cell](repeating: Cell(), count: cols), count: gridRows)
        let now = self.now

        drawTank(&grid, now)
        if visitor?.kind == .whale { drawVisitor(&grid) } // far background
        drawWeeds(&grid, now)
        drawChest(&grid, now)
        drawFood(&grid)
        drawShrimp(&grid)
        drawBubbles(&grid)
        drawJellyfish(&grid, now)
        if let v = visitor, v.kind != .whale { drawVisitor(&grid) }
        drawFish(&grid)
        drawCleanupCrew(&grid)
        drawInk(&grid)
        return grid
    }

    private func drawTank(_ grid: inout [[Cell]], _ now: Double) {
        let frame: UInt8 = 30
        for c in 0..<cols {
            grid[0][c] = Cell(ch: "-", color: frame)
            grid[bottomBorderRow][c] = Cell(ch: "-", color: frame)
        }
        for r in 0..<gridRows {
            grid[r][0] = Cell(ch: "|", color: frame)
            grid[r][cols - 1] = Cell(ch: "|", color: frame)
        }
        grid[0][0] = Cell(ch: "+", color: frame)
        grid[0][cols - 1] = Cell(ch: "+", color: frame)
        grid[bottomBorderRow][0] = Cell(ch: "+", color: frame)
        grid[bottomBorderRow][cols - 1] = Cell(ch: "+", color: frame)

        let title = Array(" ~ A Q U A R I U M ~ ")
        let titleStart = (cols - title.count) / 2

        if isNight {
            // Stars and a moon along the tank rim
            for c in 1..<(cols - 1) {
                let h = Int((UInt(c) &* 40_503) % 100)
                guard h < 9 else { continue }
                if cols > title.count + 4, c >= titleStart - 1, c <= titleStart + title.count { continue }
                let twinkle = ((tick / 6) + c) % 3 == 0
                grid[0][c] = Cell(ch: twinkle ? "*" : ".", color: twinkle ? 230 : 244, glow: true)
            }
            let moonCol = max(2, cols / 8)
            if moonCol < cols - 1 {
                grid[0][moonCol] = Cell(ch: "O", color: 223, glow: true)
            }
        } else if isSummer {
            // 여름 낮: 수면 위로 아지랑이가 흐르고 오른쪽 어깨에 태양이 뜬다
            // (여름 밤이면 위쪽 별/달 분기가 그려진다 — 계절과 조명은 직교)
            for c in 1..<(cols - 1) {
                if cols > title.count + 4, c >= titleStart - 1, c <= titleStart + title.count { continue }
                let heat = sin(Double(c) * 0.7 - now * 3)
                guard heat > 0.55 else { continue }
                grid[0][c] = Cell(ch: heat > 0.85 ? "~" : "-",
                                  color: heat > 0.85 ? 229 : 180, glow: true)
            }

            let sun: [Character] = ["\\", "-", "O", "-", "/"]
            let sunStart = cols - 1 - sun.count // 오른쪽 테두리 바로 안쪽 (밤의 달과 반대 어깨)
            if sunStart > titleStart + title.count {
                for (i, ch) in sun.enumerated() {
                    grid[0][sunStart + i] = Cell(ch: ch, color: ch == "O" ? 226 : 220, glow: true)
                }
            }
        }

        if cols > title.count + 4 {
            for (i, ch) in title.enumerated() {
                grid[0][titleStart + i] = Cell(ch: ch, color: 45)
            }
        }

        for c in 1..<(cols - 1) {
            let wave = sin(Double(c) * 0.45 + now * 2)
            let ch: Character = wave > 0.2 ? "~" : (wave < -0.6 ? "-" : " ")
            grid[surfaceRow][c] = Cell(ch: ch, color: wave > 0.2 ? 45 : 39)
        }

        for c in 1..<(cols - 1) {
            let h = Int((UInt(c) &* 2_654_435_761) % 1000)
            let sandChars: [Character] = [".", ".", "_", ",", ":"]
            let sandColors: [UInt8] = [180, 137, 143]
            grid[sandRow][c] = Cell(ch: sandChars[h % sandChars.count],
                                    color: sandColors[h % sandColors.count])
        }
    }

    private func drawWeeds(_ grid: inout [[Cell]], _ now: Double) {
        for weed in weeds {
            guard weed.x > 0, weed.x < cols - 1 else { continue }
            for i in 0..<weed.height {
                let r = sandRow - 1 - i
                guard r >= swimMinRow else { break }
                let sway = Int(now * 2 + weed.phase) + i
                grid[r][weed.x] = Cell(ch: sway % 2 == 0 ? "(" : ")",
                                       color: i % 2 == 0 ? 28 : 40)
            }
        }
    }

    private func drawChest(_ grid: inout [[Cell]], _ now: Double) {
        guard let cx = chestX else { return }
        let topRow = sandRow - 2, bottomRow = sandRow - 1
        guard topRow >= swimMinRow else { return }

        let isOpen = now < chestOpenUntil
        let top: [Character] = isOpen ? Array("\\****/") : Array(" ____ ")
        let bottom: [Character] = Array("[____]")
        let goldShimmer: [UInt8] = [220, 226, 214]

        for (i, ch) in top.enumerated() where ch != " " {
            let c = cx + i
            guard c > 0, c < cols - 1 else { continue }
            let color: UInt8 = ch == "*" ? goldShimmer[(tick / 2 + i) % goldShimmer.count] : 130
            grid[topRow][c] = Cell(ch: ch, color: color)
        }
        for (i, ch) in bottom.enumerated() {
            let c = cx + i
            guard c > 0, c < cols - 1 else { continue }
            grid[bottomRow][c] = Cell(ch: ch, color: 130)
        }
    }

    private func drawJellyfish(_ grid: inout [[Cell]], _ now: Double) {
        for j in jellyfish {
            let art: [[Character]] = j.isContracted(at: now)
                ? [Array(" (_) "), Array("  |  ")]
                : [Array("(___)"), Array(" )|( ")]
            // Bioluminescence: jellyfish glow teal at night instead of dimming
            let bellColor: UInt8 = isNight
                ? [51, 87, 123][(tick / 4) % 3]
                : [183, 189, 177][(tick / 4) % 3] // translucent shimmer
            let startR = Int(j.y.rounded())
            let startC = Int(j.x.rounded())
            for (ri, rowArt) in art.enumerated() {
                let r = startR + ri
                guard r >= swimMinRow, r <= swimMaxRow else { continue }
                for (ci, ch) in rowArt.enumerated() where ch != " " {
                    let c = startC + ci
                    guard c > 0, c < cols - 1 else { continue }
                    grid[r][c] = Cell(ch: ch,
                                      color: ri == 0 ? bellColor : (isNight ? 45 : 146),
                                      glow: isNight)
                }
            }
        }
    }

    private func drawFood(_ grid: inout [[Cell]]) {
        for pellet in food where pellet.kind == .pellet {
            let r = Int(pellet.y.rounded()), c = Int(pellet.x.rounded())
            guard r >= swimMinRow, r <= sandRow, c > 0, c < cols - 1 else { continue }
            grid[r][c] = Cell(ch: "*", color: 214)
        }
        // 수박은 3칸이라 펠릿보다 뒤에 그린다 (펠릿이 껍질을 파먹지 않게)
        for melon in food where melon.kind == .watermelon {
            let r = Int(melon.y.rounded()), c = Int(melon.x.rounded())
            guard r >= swimMinRow, r <= sandRow else { continue }
            for (dc, ch) in [(-1, Character("(")), (0, "%"), (1, ")")] {
                let x = c + dc
                guard x > 0, x < cols - 1 else { continue }
                grid[r][x] = Cell(ch: ch, color: dc == 0 ? 198 : 34) // 분홍 속 + 초록 껍질
            }
        }
    }

    private func drawShrimp(_ grid: inout [[Cell]]) {
        for (i, s) in shrimp.enumerated() {
            let r = Int(s.y.rounded()), c = Int(s.x.rounded())
            guard r >= swimMinRow, r <= swimMaxRow, c > 0, c < cols - 1 else { continue }
            let wiggle = ((tick / 2) + i) % 2 == 0
            grid[r][c] = Cell(ch: wiggle ? "~" : "-", color: wiggle ? 218 : 211)
        }
    }

    private func drawBubbles(_ grid: inout [[Cell]]) {
        for bubble in bubbles {
            let r = Int(bubble.y.rounded()), c = Int(bubble.x.rounded())
            guard r >= swimMinRow, r <= swimMaxRow, c > 0, c < cols - 1 else { continue }
            let depth = bubble.y / Double(max(1, swimMaxRow))
            let ch: Character = depth > 0.66 ? "." : (depth > 0.33 ? "o" : "O")
            grid[r][c] = Cell(ch: ch, color: 117)
        }
    }

    /// 물고기 문자 하나의 (색, 발광) 결정 — 희귀 변종은 오버레이로 색을 덮어씀
    private func fishColor(_ f: Fish, ch: Character, i: Int) -> (UInt8, Bool) {
        switch f.morph {
        case .normal:
            if ch == "°" { return (231, false) }
            if allSpecies[f.species].striped { return (i % 2 == 0 ? f.color : f.color2, false) }
            return (f.color, false)
        case .rainbow:
            return ch == "°" ? (231, true) : (rainbowPalette[(tick / 3 + i) % rainbowPalette.count], true)
        case .glowing:
            return ch == "°" ? (231, true) : ([51, 87, 123][(tick / 4) % 3], true)
        case .golden:
            return ch == "°" ? (231, true) : ([220, 226, 214][(tick / 2 + i) % 3], true)
        case .shadow:
            return ch == "°" ? (196, false) : (238, false) // 붉은 눈, 어두운 몸통 (밤엔 감광되어 은밀)
        }
    }

    private func drawFish(_ grid: inout [[Cell]]) {
        for f in fish {
            let r = Int(f.y.rounded())
            guard r >= swimMinRow, r <= swimMaxRow else { continue }
            let startC = Int(f.x.rounded())
            for (i, ch) in f.art.enumerated() {
                let c = startC + i
                guard c > 0, c < cols - 1 else { continue }
                let (color, glow) = fishColor(f, ch: ch, i: i)
                grid[r][c] = Cell(ch: ch, color: color, glow: glow)
            }
        }

        if isNight {
            // Sleeping fish exhale a little "z" now and then
            for (i, f) in fish.enumerated() where ((tick / 18) + i) % 7 == 0 {
                let r = Int(f.y.rounded()) - 1
                let c = Int(f.mouthX.rounded())
                if r >= swimMinRow, c > 0, c < cols - 1, grid[r][c].ch == " " {
                    grid[r][c] = Cell(ch: "z", color: 250)
                }
            }
        }
    }

    private func drawVisitor(_ grid: inout [[Cell]]) {
        guard let v = visitor else { return }
        let art = visitorArt(v)
        let baseColor: UInt8
        switch v.kind {
        case .whale: baseColor = 24    // distant deep blue
        case .turtle: baseColor = 71
        case .octopus: baseColor = 168
        case .sunfish: baseColor = 145 // 은빛 회색
        }
        let startR = Int(v.y.rounded())
        let startC = Int(v.x.rounded())
        for (ri, rowArt) in art.enumerated() {
            let r = startR + ri
            guard r >= swimMinRow, r <= swimMaxRow else { continue }
            for (ci, ch) in rowArt.enumerated() where ch != " " {
                let c = startC + ci
                guard c > 0, c < cols - 1 else { continue }
                let isEye = ch == "°" || (v.kind == .whale && ch == "o")
                grid[r][c] = Cell(ch: ch, color: isEye ? 231 : baseColor)
            }
        }
    }

    private func drawInk(_ grid: inout [[Cell]]) {
        guard let cloud = inkCloud else { return }
        let age = now - cloud.bornAt
        let density = max(0, 1 - age / 4)
        let chars: [Character] = ["%", "#", "*"]
        for dy in -2...2 {
            for dx in -6...6 {
                let r = Int(cloud.y.rounded()) + dy
                let c = Int(cloud.x.rounded()) + dx
                guard r >= swimMinRow, r <= swimMaxRow, c > 0, c < cols - 1 else { continue }
                let h = Int((UInt(bitPattern: (dx &+ 7) &* 31 &+ (dy &+ 3) &* 131 &+ tick / 3) &* 2_654_435_761) % 100)
                guard Double(h) < density * 55 else { continue }
                grid[r][c] = Cell(ch: chars[h % chars.count], color: 239)
            }
        }
    }

    private func drawCleanupCrew(_ grid: inout [[Cell]]) {
        let r = sandRow - 1
        guard r >= swimMinRow else { return }

        for s in snails {
            let c = Int(s.x.rounded())
            if c > 0, c < cols - 1 {
                grid[r][c] = Cell(ch: "@", color: 180)
            }
        }

        for crab in crabs {
            let art: [Character]
            switch crab.mode {
            case .waving:
                art = (tick / 4) % 2 == 0 ? Array("Y(;,;)v") : Array("v(;,;)Y")
            default:
                art = Array("v(;,;)v")
            }
            let startC = Int(crab.x.rounded())
            for (i, ch) in art.enumerated() {
                let c = startC + i
                guard c > 0, c < cols - 1 else { continue }
                grid[r][c] = Cell(ch: ch, color: 209)
            }
        }
    }

    private func statusLine(_ now: Double) -> String {
        let elapsed = Int(now - startTime)
        let timeStr = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        let days = max(1, Int((Date().timeIntervalSince1970 - tankBornAt) / 86400) + 1)
        let modeLabel = L10n.modeLabel(auto: lighting == .auto, night: isNight)
        let sep = ANSI.fg(240) + "  |  "
        var line = ANSI.fg(51) + " " + L10n.statusFish(fish.count)
            + sep + ANSI.fg(214) + L10n.statusFood(food.count + shrimp.count)
            + sep + ANSI.fg(250) + L10n.statusDay(days, timeStr)
            + sep + ANSI.fg(147) + modeLabel
            + (MusicPlayer.shared.isPlaying ? ANSI.fg(219) + " ♪" : "")
        if let deadline = focusUntil {
            let remain = max(0, Int(deadline - now))
            let clock = String(format: "%d:%02d", remain / 60, remain % 60)
            line += sep + ANSI.fg(203) + L10n.statusFocus(clock)
        }
        let unread = mailbox.filter { !$0.read }.count
        if unread > 0 { line += sep + ANSI.fg(213) + L10n.statusUnread(unread) }
        if lounge {
            // 키바인드 목록은 대부분의 키가 막힌 무인 전시에선 무용하다.
            // 15초마다 한 줄씩 돌아가며 지나가는 사람에게 말을 건다.
            let i = Int((now - startTime) / 15) % L10n.loungeHintCount
            line += sep + ANSI.fg(245) + L10n.loungeHint(i)
        } else {
            line += sep + ANSI.fg(245) + L10n.helpLine
        }
        if now < messageUntil {
            line += ANSI.fg(213) + "   " + message
        }
        return line + ANSI.reset
    }

    // MARK: - Roster panel (도감)

    /// Hangul renders 2 columns wide in the terminal.
    private func displayWidth(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { width, scalar in
            let wide = (0xAC00...0xD7A3).contains(scalar.value)
                || (0x1100...0x115F).contains(scalar.value)
                || (0x3130...0x318F).contains(scalar.value)
            return width + (wide ? 2 : 1)
        }
    }

    private func pad(_ s: String, to width: Int) -> String {
        s + String(repeating: " ", count: max(0, width - displayWidth(s)))
    }

    /// 긴 물고기(갈치 등) 아트를 도감 컬럼 폭에 맞게 축약 — 정렬·박스 유지
    private func artGlyph(_ f: Fish, max: Int) -> String {
        let s = String(f.art)
        return s.count <= max ? s : String(s.prefix(max - 1)) + "~"
    }

    private func pos(_ row: Int, _ col: Int) -> String {
        "\u{1B}[\(row);\(col)H"
    }

    /// 도감에서 희귀 물고기 줄 색상 (normal은 기본 회백색)
    private func morphRosterColor(_ morph: Morph) -> UInt8 {
        switch morph {
        case .normal: return 252
        case .rainbow: return 201
        case .glowing: return 51
        case .golden: return 220
        case .shadow: return 240
        }
    }

    /// Drawn with absolute cursor positioning over the live tank, so
    /// double-width Hangul can't shift the grid cells around it.
    private func rosterOverlay() -> String {
        guard cols >= 50, gridRows >= 12 else {
            return pos(3, 3) + ANSI.fg(220) + " " + L10n.rosterEnlarge + " " + ANSI.reset
        }
        let innerW = min(46, cols - 8)
        let maxList = max(1, gridRows - 9)
        let sorted = fish.sorted { $0.bornAtEpoch < $1.bornAtEpoch }
        let shown = sorted.prefix(maxList)
        let nowEpoch = Date().timeIntervalSince1970

        var lines: [(text: String, color: UInt8)] = []
        for f in shown {
            let days = Int((nowEpoch - f.bornAtEpoch) / 86400)
            let age = days <= 0 ? L10n.rosterToday : L10n.rosterDays(days)
            let line = " " + pad(f.name, to: 9) + pad(artGlyph(f, max: 7), to: 8)
                + pad(L10n.personalityLabel(f.personality), to: 6)
                + pad(age, to: 7) + L10n.rosterEaten(f.eaten)
            lines.append((line, morphRosterColor(f.morph)))
        }
        if sorted.count > shown.count {
            lines.append((" " + L10n.rosterMore(sorted.count - shown.count), 245))
        }
        lines.append(("", 252))
        let seen = " " + L10n.rosterVisitors(whale: visitorSeen["whale", default: 0],
                                             turtle: visitorSeen["turtle", default: 0],
                                             octopus: visitorSeen["octopus", default: 0])
        lines.append((seen, 117))
        if visitorSeen["sunfish", default: 0] > 0 {
            lines.append((" " + L10n.rosterSunfish(visitorSeen["sunfish", default: 0]), 117))
        }
        if focusDone > 0 {
            lines.append((" " + L10n.rosterFocus(focusDone), 203))
        }
        if commitRewards > 0 {
            lines.append((" " + L10n.rosterCommits(commitRewards), 114))
        }
        lines.append((" " + L10n.rosterAchievements(unlocked.count, Achievements.all.count), 226))
        let travelers = fish.filter { !$0.origin.isEmpty }.count
        if travelers > 0 {
            lines.append((" " + L10n.rosterTravelers(travelers), 111))
        }

        let startRow = 3
        let startCol = max(2, (cols - innerW - 2) / 2 + 1)
        let title = L10n.rosterTitle(fish.count)
        var out = pos(startRow, startCol) + ANSI.fg(245) + "+-"
            + ANSI.fg(51) + title
            + ANSI.fg(245) + String(repeating: "-", count: max(0, innerW - displayWidth(title) - 1)) + "+"
        var r = startRow + 1
        for line in lines {
            guard r < rows - 1 else { break }
            out += pos(r, startCol) + ANSI.fg(245) + "|"
                + ANSI.fg(line.color) + pad(line.text, to: innerW)
                + ANSI.fg(245) + "|"
            r += 1
        }
        out += pos(r, startCol) + ANSI.fg(245) + "+" + String(repeating: "-", count: innerW) + "+"
        return out + ANSI.reset
    }

    /// 받은편지함 패널 (b 키)
    private func mailboxOverlay() -> String {
        guard cols >= 50, gridRows >= 12 else {
            return pos(3, 3) + ANSI.fg(220) + " " + L10n.mailboxEnlarge + " " + ANSI.reset
        }
        let innerW = min(54, cols - 8)
        let maxCards = max(1, (gridRows - 8) / 2)
        let sorted = mailbox.sorted { $0.at > $1.at }

        var lines: [(text: String, color: UInt8)] = []
        if sorted.isEmpty {
            lines.append((" " + L10n.mailboxEmpty, 245))
        } else {
            for pc in sorted.prefix(maxCards) {
                let head = " \u{1F4EC} \(pc.from) · \(L10n.postcardLocation(pc.location)) · \(L10n.relativeTime(pc.at))"
                lines.append((head, 117))
                lines.append(("     \u{201C}\(L10n.postcardMessage(pc.message))\u{201D}", 252))
            }
            if sorted.count > maxCards {
                lines.append((" " + L10n.rosterMore(sorted.count - maxCards), 245))
            }
        }

        let startRow = 3
        let startCol = max(2, (cols - innerW - 2) / 2 + 1)
        let title = L10n.mailboxTitle(mailbox.count)
        var out = pos(startRow, startCol) + ANSI.fg(245) + "+-"
            + ANSI.fg(213) + title
            + ANSI.fg(245) + String(repeating: "-", count: max(0, innerW - displayWidth(title) - 1)) + "+"
        var r = startRow + 1
        for line in lines {
            guard r < rows - 1 else { break }
            out += pos(r, startCol) + ANSI.fg(245) + "|"
                + ANSI.fg(line.color) + pad(line.text, to: innerW)
                + ANSI.fg(245) + "|"
            r += 1
        }
        out += pos(r, startCol) + ANSI.fg(245) + "+" + String(repeating: "-", count: innerW) + "+"
        return out + ANSI.reset
    }

    /// 후원 안내 패널 (s 키)
    private func sponsorOverlay() -> String {
        guard cols >= 50, gridRows >= 10 else {
            return pos(3, 3) + ANSI.fg(220) + " " + L10n.sponsorEnlarge + " " + ANSI.reset
        }
        let innerW = min(52, cols - 8)
        let lines: [(text: String, color: UInt8)] = [
            (" " + L10n.sponsorThanks1, 252),
            (" " + L10n.sponsorThanks2, 252),
            ("", 252),
            (" \u{2615}  " + Support.display, 45),
            ("", 252),
            (" " + L10n.sponsorOpenHint, 245),
        ]
        let startRow = 4
        let startCol = max(2, (cols - innerW - 2) / 2 + 1)
        let title = L10n.sponsorTitle
        var out = pos(startRow, startCol) + ANSI.fg(245) + "+-"
            + ANSI.fg(219) + title
            + ANSI.fg(245) + String(repeating: "-", count: max(0, innerW - displayWidth(title) - 1)) + "+"
        var r = startRow + 1
        for line in lines {
            guard r < rows - 1 else { break }
            out += pos(r, startCol) + ANSI.fg(245) + "|"
                + ANSI.fg(line.color) + pad(line.text, to: innerW)
                + ANSI.fg(245) + "|"
            r += 1
        }
        out += pos(r, startCol) + ANSI.fg(245) + "+" + String(repeating: "-", count: innerW) + "+"
        return out + ANSI.reset
    }

    /// 라운지 설치 QR. 다른 패널과 달리 +---+ 테두리를 두르지 않는다 —
    /// QR은 사방 4모듈의 *밝은* 여백이 있어야 스캐너가 경계를 찾는데,
    /// ASCII 테두리는 여백 노릇을 못 하고 오히려 코드를 침범한다.
    ///
    /// 그리드 셀이 아니라 오버레이로 그리는 이유: render()에서 오버레이는 그리드
    /// 뒤에 붙으므로 dimmed()를 통째로 우회한다. 그리드에 넣었다면 밤에 명암이
    /// 뭉개져 스캔이 안 되고, 셀마다 glow를 강제해야 했다.
    private func loungeQROverlay() -> String {
        guard let modules = qrModules, let qrCols = modules.first?.count else { return "" }
        let qrRows = modules.count / 2 // 하프블록 한 줄 = 모듈 두 행

        // 우측 하단. 행 0은 제목·달(cols/8)·여름 태양(오른쪽 어깨)이 이미 쓰고 있다.
        // 아래에서부터 쌓지 않으면 모래와 바닥 테두리를 덮어 "자갈에 파묻힌 QR"이 된다.
        let bottom = sandRow           // 1-based 터미널 행 = 그리드 sandRow-1 (모래 바로 위)
        let top = bottom - qrRows + 1
        let left = cols - qrCols - 2
        // 캡션 한 줄(top-1)까지 자리가 나와야 하고, 물고기가 헤엄칠 여유도 남겨둔다.
        // 코드가 작아지면서 좁은 창에도 들어가게 됐지만, 어항의 절반을 넘게 차지하면
        // 수조가 아니라 QR을 전시하는 꼴이라 그때는 통째로 접는다.
        let swimHeight = swimMaxRow - swimMinRow + 1
        guard qrCols + 6 <= cols, top >= swimMinRow + 3, bottom < rows,
              qrRows * 2 <= swimHeight else { return "" }

        // 밝은 터미널이면 흰 카드를 깔지 않고 배경을 그대로 비춘다. 밝은 모듈이
        // 터미널 배경색이 되므로 여전히 균일하고, 화면에서 차지하는 무게가 확 준다.
        // 어두운 터미널·응답 없는 터미널은 흰 카드를 유지한다 — 검은 모듈을 어두운
        // 배경에 그리면 대비가 사라지고, 반전 QR은 못 읽는 스캐너가 있다.
        let seeThrough = terminalDark == false

        let caption = L10n.loungeQRCaption
        let capCol = max(1, left + (qrCols - displayWidth(caption)) / 2)
        var out = pos(top - 1, capCol) + ANSI.fg(seeThrough ? 240 : 231) + caption

        if seeThrough {
            // 배경을 안 칠하니 색 지정이 앞에 한 번이면 끝난다 (프레임 바이트도 준다).
            out += ANSI.bgDefault + ANSI.fg(16)
            for r in 0..<qrRows {
                out += pos(top + r, left)
                for c in 0..<qrCols {
                    let up = modules[r * 2][c], down = modules[r * 2 + 1][c]
                    // 밝은 모듈은 공백 — 배경을 칠하지 않되 뒤의 수조는 지워진다.
                    out.append(up && down ? "\u{2588}" : up ? "\u{2580}" : down ? "\u{2584}" : " ")
                }
            }
        } else {
            for r in 0..<qrRows {
                out += pos(top + r, left)
                var lastPair: (UInt8, UInt8)? = nil
                for c in 0..<qrCols {
                    // ▀ 는 전경색이 위쪽 절반, 배경색이 아래쪽 절반을 칠한다.
                    // 터미널 셀이 대략 세로:가로 2:1이라 이 매핑에서 모듈이 정사각형이 된다.
                    let pair: (UInt8, UInt8) = (modules[r * 2][c] ? 16 : 231,
                                                modules[r * 2 + 1][c] ? 16 : 231)
                    if pair != lastPair ?? (255, 255) {
                        out += ANSI.fg(pair.0) + ANSI.bg(pair.1)
                        lastPair = pair
                    }
                    out.append("\u{2580}")
                }
            }
        }
        // 배경색을 남긴 채 끝내면 다음 프레임 그리드에 색 줄무늬로 번진다
        // (render()는 전경색만 디핑하고 매 프레임 clear를 하지 않는다).
        return out + ANSI.reset
    }
}
