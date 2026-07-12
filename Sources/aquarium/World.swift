import Foundation

struct Cell {
    var ch: Character = " "
    var color: UInt8 = 252
    var glow: Bool = false // glowing cells skip night-time dimming
}

enum Lighting: String {
    case auto, day, night
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
    var id: String = UUID().uuidString
    var origin: [String] = []   // 거쳐온 어항들 (여권)
    var morph: Morph = .normal  // 희귀 변종

    var art: [Character] { dir > 0 ? allSpecies[species].right : allSpecies[species].left }
    var mouthX: Double { dir > 0 ? x + Double(art.count - 1) : x }
}

struct Bubble {
    var x: Double
    var y: Double
    var phase: Double
    var speed: Double
}

struct Food {
    var x: Double
    var y: Double
    var vy: Double
    var restingSince: Double?
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
    case whale, turtle, octopus
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

    var isNight: Bool { lighting == .night || (lighting == .auto && envNight) }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    // Vertical layout (0-indexed grid rows; the last terminal row is the status line)
    private var gridRows: Int { rows - 1 }
    private var surfaceRow: Int { 1 }
    private var bottomBorderRow: Int { gridRows - 1 }
    private var sandRow: Int { gridRows - 2 }
    private var swimMinRow: Int { 2 }
    private var swimMaxRow: Int { sandRow - 1 }

    private var maxFish: Int { max(8, min(40, cols * rows / 80)) }

    init(cols: Int, rows: Int, terminalDark: Bool? = nil, restoring save: SaveState? = nil,
         ephemeral: Bool = false) {
        self.cols = cols
        self.rows = rows
        self.terminalDark = terminalDark
        self.ephemeral = ephemeral
        startTime = ProcessInfo.processInfo.systemUptime
        nextBreed = startTime + Double.random(in: 900...1500)
        tankBornAt = Date().timeIntervalSince1970
        nextVisitorAt = startTime + (debugVisitor != nil ? 4 : Double.random(in: 120...300))
        plantWeeds()
        placeChest()
        spawnJellyfish()
        spawnCleanupCrew()
        if let save, !save.fish.isEmpty {
            restore(save)
        } else {
            for _ in 0..<5 { spawnAdult() }
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
        for i in fish.indices { clampToTank(&fish[i]) }
        food.removeAll { $0.x >= Double(cols - 1) }
        bubbles.removeAll { $0.x >= Double(cols - 1) }
    }

    // MARK: - Persistence

    private func restore(_ save: SaveState) {
        let now = self.now
        tankBornAt = save.tankBornAt
        lighting = Lighting(rawValue: save.lighting) ?? .auto
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
            remaining = Double.random(in: 900...1500)
            if bornAges.count < maxOfflineBirths, fish.count + bornAges.count < maxFish {
                bornAges.append(away) // seconds this fish has already lived
            }
        }
        nextBreed = now + (remaining - away)

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
                          morph: f.morph == .normal ? nil : f.morph.rawValue)
            },
            visitorSeen: visitorSeen,
            focusDone: focusDone,
            tankFull: fish.count >= maxFish,
            commitRewards: commitRewards,
            stats: stats,
            unlockedAchievements: Array(unlocked),
            travelers: travelers.isEmpty ? nil : travelers,
            mailbox: mailbox.isEmpty ? nil : mailbox)
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
        clampToTank(&f)
        fish.append(f)
    }

    /// FishState → Fish 복원 (restore와 입양이 공유)
    private func makeFish(from state: FishState) -> Fish {
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
        usedNames.insert(f.name)
        clampToTank(&f)
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
        clampToTank(&baby)
        fish.append(baby)
        bump("born")
        return baby.name
    }

    private func clampToTank(_ f: inout Fish) {
        let maxX = Double(max(2, cols - 2 - f.art.count))
        f.x = min(max(1, f.x), maxX)
        f.y = min(max(Double(swimMinRow), f.y), Double(max(swimMinRow, swimMaxRow)))
    }

    // MARK: - Input

    func feed() {
        guard food.count < 60 else { return }
        sprinkleFood(Int.random(in: 4...7))
        bump("feedActions")
        post(L10n.foodSprinkled)
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
        nextBreed -= Double(commits) * 30
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
            let r = Int(f.y.rounded())
            let c0 = Int(f.x.rounded())
            guard abs(r - row) <= 1, col >= c0 - 1, col <= c0 + f.art.count else { continue }

            post(L10n.touched(f.name))
            bump("touch"); if isNight { bump("touchNight") }
            Sound.playTouch()
            fish[i].panicUntil = now + 1.5
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

        updateFish(now)
        updateFood(now)
        updateShrimp(now)
        updateBubbles(now)
        updateJellyfish(now)
        updateChest(now)
        updateCleanupCrew(now)
        updateVisitor(now)

        // The tank slowly fills up on its own; feeding just speeds it along.
        if now >= nextBreed {
            nextBreed = now + Double.random(in: 900...1500)
            if fish.count < maxFish, let parent = fish.randomElement() {
                let name = spawnBaby(near: parent)
                post(L10n.babyBorn(name, count: fish.count))
            } else if fish.count >= maxFish {
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
    }

    private func updateFish(_ now: Double) {
        for i in fish.indices {
            var f = fish[i]

            if now < f.panicUntil {
                // Touched! Dart away from the finger
                f.x += f.dir * f.speed * 3.5
            } else if let target = nearestPrey(for: f) {
                let dx = target.x - f.mouthX
                if abs(dx) > 1 { f.dir = dx > 0 ? 1 : -1 }
                f.vy = max(-0.3, min(0.3, (target.y - f.y) * 0.12))
                f.x += f.dir * f.speed * 1.8
            } else if isNight {
                // Sleepy drift: slow, near the bottom, rarely turning
                if Double.random(in: 0...1) < 0.003 { f.dir = -f.dir }
                if f.y < Double(swimMaxRow - 2) { f.vy += 0.003 }
                f.x += f.dir * f.speed * 0.25
            } else {
                if Double.random(in: 0...1) < 0.01 { f.dir = -f.dir }
                if Double.random(in: 0...1) < 0.05 { f.vy = Double.random(in: -0.1...0.1) }
                f.x += f.dir * f.speed
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
                    food.remove(at: fi)
                    f.eaten += 1
                    bump("meals")
                    nextBreed -= 30 // well-fed tanks grow faster
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
                    nextBreed -= 45 // live food is extra nutritious
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

    private func nearestPrey(for f: Fish) -> (x: Double, y: Double)? {
        var best: (x: Double, y: Double)?
        var bestScore = Double.infinity
        for pellet in food where abs(pellet.x - f.x) < 28 {
            let score = pow(pellet.x - f.x, 2) + pow((pellet.y - f.y) * 2, 2)
            if score < bestScore {
                bestScore = score
                best = (pellet.x, pellet.y)
            }
        }
        for s in shrimp where abs(s.x - f.x) < 28 {
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
        case .whale, .turtle:
            v.x += v.dir * (v.kind == .whale ? 0.28 : 0.18)
            if v.kind == .turtle { v.y += sin(now * 1.2) * 0.03 }
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
        var kind = VisitorKind(rawValue: debugVisitor ?? "") ?? VisitorKind.allCases.randomElement()!
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
        }
        visitorSeen[kind.rawValue, default: 0] += 1
    }

    private func scheduleNextVisitor(_ now: Double) {
        nextVisitorAt = now + (debugVisitor != nil
            ? Double.random(in: 15...25)
            : Double.random(in: 240...600))
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
    private func ingestAdoptions() {
        for token in AdoptInbox.drain() {
            guard let state = Passport.decode(token) else { continue }
            if let id = state.id, fish.contains(where: { $0.id == id }) { continue } // 중복 붙여넣기 방지
            let f = makeFish(from: state)
            fish.append(f)
            bump("adopted")
            post(L10n.adopted(f.name, from: f.origin.last))
            Sound.playChime()
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

        var out = ANSI.home
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
        return out
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
        for pellet in food {
            let r = Int(pellet.y.rounded()), c = Int(pellet.x.rounded())
            guard r >= swimMinRow, r <= sandRow, c > 0, c < cols - 1 else { continue }
            grid[r][c] = Cell(ch: "*", color: 214)
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
        line += sep + ANSI.fg(245) + L10n.helpLine
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
            let line = " " + pad(f.name, to: 11) + pad(artGlyph(f, max: 9), to: 10)
                + pad(age, to: 9) + L10n.rosterEaten(f.eaten)
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
}
