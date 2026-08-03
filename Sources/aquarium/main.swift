import Foundation

let appVersion = "3.1.0"

func printStatus() {
    guard let save = SaveStore.load(), !save.fish.isEmpty else {
        print(L10n.statusNoTank)
        return
    }
    let nowEpoch = Date().timeIntervalSince1970
    let days = max(1, Int((nowEpoch - save.tankBornAt) / 86400) + 1)
    let remaining = save.breedRemaining - (nowEpoch - save.savedAt)
    let breedText: String
    if save.tankFull == true {
        breedText = L10n.statusTankFull
    } else if remaining <= 0 {
        breedText = L10n.statusBabyWaiting
    } else if remaining >= 90 {
        breedText = L10n.statusNextBirthMinutes(Int(remaining / 60))
    } else {
        breedText = L10n.statusNextBirthSeconds(Int(remaining))
    }
    print(L10n.statusLine(count: save.fish.count, days: days, breed: breedText))
}

func installHook() {
    let git = Process()
    git.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    git.arguments = ["git", "rev-parse", "--git-path", "hooks"]
    let pipe = Pipe()
    git.standardOutput = pipe
    git.standardError = Pipe()
    guard (try? git.run()) != nil else {
        print(L10n.hookNoRepo)
        exit(1)
    }
    git.waitUntilExit()
    guard git.terminationStatus == 0,
          let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
        print(L10n.hookNoRepo)
        exit(1)
    }

    let hooksDir = output.trimmingCharacters(in: .whitespacesAndNewlines)
    let hookPath = hooksDir + "/post-commit"
    let rewardLine = "command -v aquarium >/dev/null 2>&1 && aquarium --reward"
    let fm = FileManager.default
    try? fm.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

    if let existing = try? String(contentsOfFile: hookPath, encoding: .utf8) {
        if existing.contains("aquarium --reward") {
            print(L10n.hookAlreadyInstalled)
            return
        }
        try? (existing + "\n" + rewardLine + "\n").write(toFile: hookPath, atomically: true, encoding: .utf8)
    } else {
        try? ("#!/bin/sh\n" + rewardLine + "\n").write(toFile: hookPath, atomically: true, encoding: .utf8)
    }
    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath)
    print(L10n.hookInstalled(hookPath))
}

func printMailbox() {
    guard let save = SaveStore.load(), let mail = save.mailbox, !mail.isEmpty else {
        print(L10n.mailboxEmpty)
        return
    }
    print(ANSI.fg(213) + L10n.mailboxTitle(mail.count) + ANSI.reset)
    for pc in mail.sorted(by: { $0.at > $1.at }) {
        print(ANSI.fg(117) + "  \u{1F4EC} \(pc.from) · \(L10n.postcardLocation(pc.location)) · \(L10n.relativeTime(pc.at))"
              + ANSI.reset)
        print(ANSI.fg(252) + "     \u{201C}\(L10n.postcardMessage(pc.message))\u{201D}" + ANSI.reset)
    }
}

func printHelp() {
    print(L10n.helpText)
}

var arguments = Array(CommandLine.arguments.dropFirst())

var focusMinutes: Int?
if let index = arguments.firstIndex(of: "--focus") {
    arguments.remove(at: index)
    if index < arguments.count, let minutes = Int(arguments[index]) {
        focusMinutes = minutes
        arguments.remove(at: index)
    } else {
        focusMinutes = 25
    }
}

var seasonOverride: Season?
if let index = arguments.firstIndex(of: "--season") {
    arguments.remove(at: index)
    let value = index < arguments.count ? arguments[index] : ""
    guard let parsed = Season(rawValue: value) else {
        fputs(L10n.invalidSeason(value) + "\n", stderr)
        exit(1)
    }
    seasonOverride = parsed
    arguments.remove(at: index)
}

// 값을 안 받지만 --status 류와 달리 메인 루프로 진행하므로, 미지 옵션 가드에
// 걸리지 않게 arguments에서 반드시 제거한다.
var loungeMode = false
if let index = arguments.firstIndex(of: "--lounge") {
    arguments.remove(at: index)
    loungeMode = true
}

// --lounge와 같은 이유로 arguments에서 반드시 제거한다 (위 주석 참고).
// --lounge 없이 단독으로도 쓸 수 있다 — 마이크는 이 플래그가 있을 때만 열리므로
// 프라이버시 후퇴가 없고, 데스크에서 감지 임계를 튜닝할 수 있어야 한다.
var clapMode = false
if let index = arguments.firstIndex(of: "--clap") {
    arguments.remove(at: index)
    clapMode = true
}

// 문서화하지 않는 테스트 훅 — AQUARIUM_LOUNGE_FAST와 같은 성격.
// 인자·TTY와 무관해야 하므로 서브커맨드 디스패치보다 앞에 둔다.
if ProcessInfo.processInfo.environment["AQUARIUM_CLAP_SELFTEST"] == "1" {
    exit(ClapSelfTest.run() ? 0 : 1)
}

if arguments.contains("--status") {
    printStatus()
    exit(0)
}
if arguments.contains("--card") {
    Card.generate()
    exit(0)
}
if arguments.contains("--reward") {
    print(L10n.rewardDeposited(RewardInbox.deposit()))
    exit(0)
}
if arguments.contains("--achievements") {
    Achievements.printAll()
    exit(0)
}
if arguments.contains("--mailbox") {
    printMailbox()
    exit(0)
}
if arguments.contains("--sponsor") {
    Support.printCLI()
    exit(0)
}
if let i = arguments.firstIndex(of: "--release") {
    let name = (i + 1 < arguments.count) ? arguments[i + 1] : ""
    guard !name.isEmpty else {
        fputs("사용법: aquarium --release <물고기 이름>\n", stderr)
        exit(1)
    }
    Passport.release(name: name)
    exit(0)
}
if let i = arguments.firstIndex(of: "--adopt") {
    let code = (i + 1 < arguments.count) ? arguments[i + 1] : ""
    guard !code.isEmpty else {
        fputs("사용법: aquarium --adopt <분양 코드>\n", stderr)
        exit(1)
    }
    Passport.adopt(code: code)
    exit(0)
}
if arguments.contains("--install-hook") {
    installHook()
    exit(0)
}
if arguments.contains("--help") || arguments.contains("-h") {
    printHelp()
    exit(0)
}
if arguments.contains("--version") {
    print("aquarium \(appVersion)")
    exit(0)
}
if let unknown = arguments.first {
    fputs(L10n.unknownOption(unknown) + "\n", stderr)
    exit(1)
}

// 마이크 권한 창과 안내문은 raw 모드·대체화면 **이전**이어야 한다. 뒤로 가면
// (a) 전체화면 수조 위로 시스템 다이얼로그가 뜨고, (b) 사람이 읽어야 할 안내가
// 대체화면에 묻히고, (c) 다이얼로그 대기 중에 죽으면 터미널이 raw 모드로 남는다.
//
// 엔진은 여기서만 띄운다 — World.init이나 update()에서 띄우면 Card.swift의
// 헤드리스 World가 `aquarium --card` 도중에 마이크를 연다.
let clapListener: ClapListener? = clapMode ? ClapListener() : nil
if let clapListener, !ClapPermission.bringUp(clapListener) {
    print(L10n.clapDisabled)
    // 대체화면이 화면을 덮기 전에 읽을 시간을 준다.
    if isatty(STDOUT_FILENO) == 1 {
        fflush(stdout)
        usleep(2_000_000)
    }
}

let term = Terminal.shared
term.setup()

// Query the terminal theme before the main loop so the OSC reply
// can't be mistaken for keystrokes.
let terminalDark = term.backgroundIsDark()

let initialSize = term.size
let world = World(cols: initialSize.cols, rows: initialSize.rows,
                  terminalDark: terminalDark, restoring: SaveStore.load(),
                  lounge: loungeMode)
if let focusMinutes {
    world.startFocus(minutes: focusMinutes)
}
if let seasonOverride {
    world.setSeason(seasonOverride)
}

func shutdown() -> Never {
    world.writeSave()
    Terminal.shared.teardown()
    print(L10n.goodbye)
    exit(0)
}

// Registered after `world` exists — the handlers reference it via shutdown().
signal(SIGINT) { _ in shutdown() }
signal(SIGTERM) { _ in shutdown() }

/// 연출 검증용 탈출구 — 마이크 없이 c 키로 world.clap()을 직접 때려 성격별
/// 반응·불응기·입장 가드를 잴 수 있다. AQUARIUM_LOUNGE_FAST와 같은 성격이라
/// --help·README에는 싣지 않는다. (c는 현재 아무 데도 안 쓰이는 키다.)
let clapDebug = ProcessInfo.processInfo.environment["AQUARIUM_CLAP_DEBUG"] != nil

let frameMicroseconds: UInt32 = 80_000 // ~12.5 fps, plenty for a calm tank

mainLoop: while true {
    let (cols, rows) = term.size
    if cols != world.cols || rows != world.rows {
        world.resize(cols: cols, rows: rows)
    }

    for event in term.readEvents() {
        switch event {
        case .key(let key):
            // 라운지는 아무도 못 만지는 전시용이라 순간적 인터랙션(먹이·클릭)만 남기고
            // 상태를 지속적으로 바꾸는 키는 전부 무시한다. q는 되살릴 사람이 없어서,
            // o는 전체화면 위로 브라우저 창을 띄워서, 패널·음악은 켜둔 채 방치되면
            // 전시가 계속 가려지거나 종일 소리가 나서 막는다. 종료는 Ctrl-C(SIGINT).
            if world.lounge, !(clapDebug ? "fFgGcC" : "fFgG").contains(key) { break }
            switch key {
            case "c", "C":
                if clapDebug { world.clap() }   // env가 없으면 c는 그대로 무반응
            case "f", "F":
                world.feed()
            case "g", "G":
                world.feedLive()
            case "n", "N":
                world.toggleLighting()
            case "t", "T":
                world.toggleSeason()
            case "i", "I":
                world.toggleRoster()
            case "m", "M":
                world.toggleMusic()
            case "b", "B":
                world.toggleMailbox()
            case "s", "S":
                world.toggleSponsor()
            case "o", "O":
                world.openSponsor()
            case "p", "P":
                world.toggleFocus()
            case "q", "Q":
                break mainLoop
            default:
                break
            }
        case .click(let col, let row):
            world.touch(col: col, row: row)
        }
    }

    // 오디오 스레드는 플래그만 세우고 소비는 여기서 한다 — World는 오디오
    // 스레드에서 절대 건드리지 않는다. updateFish의 `var f = fish[i] … fish[i] = f`
    // 패턴은 두 번째 스레드가 fish를 만지면 조용히 깨진다.
    if let clapListener {
        // 표시자·힌트가 "플래그를 줬다"가 아니라 "마이크가 실제로 소리를 듣고
        // 있다"를 반영해야 하므로 매 프레임 갱신한다 (isLive는 신호 기반).
        world.clapLive = clapListener.isLive
        if clapListener.consumeClap() { world.clap() }
    }

    world.update()
    fputs(world.render(), stdout)
    fflush(stdout)
    usleep(frameMicroseconds)
}

shutdown()
