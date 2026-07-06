import Foundation

let appVersion = "1.6.0"

func printStatus() {
    guard let save = SaveStore.load(), !save.fish.isEmpty else {
        print("><> 아직 어항이 없어요 — aquarium 을 실행해 물고기를 만나보세요!")
        return
    }
    let nowEpoch = Date().timeIntervalSince1970
    let days = max(1, Int((nowEpoch - save.tankBornAt) / 86400) + 1)
    let remaining = save.breedRemaining - (nowEpoch - save.savedAt)
    let breedText: String
    if remaining <= 0 {
        breedText = "아기가 기다리고 있어요!"
    } else if remaining >= 90 {
        breedText = "다음 탄생까지 \(Int(remaining / 60))분"
    } else {
        breedText = "다음 탄생까지 \(Int(remaining))초"
    }
    print("><> \(save.fish.count)마리 · \(days)일째 · \(breedText)")
}

func printHelp() {
    print("""
    aquarium — 터미널 속 힐링 ASCII 어항

    사용법:
      aquarium             어항 실행
      aquarium --status    저장된 어항 요약 한 줄 출력 (tmux 상태바용)
      aquarium --version   버전 출력

    키:
      f  먹이 주기          g  생먹이(브라인슈림프)
      i  도감               n  조명 (자동 → 밤 → 낮)
      m  음악 (칩튠 플레이리스트 켜기/끄기)
      q  종료 (자동 저장)   마우스 클릭: 물고기 만지기

    환경변수:
      AQUARIUM_VISITOR=whale|turtle|octopus   손님이 자주 옵니다 (이스터에그)
    """)
}

let arguments = CommandLine.arguments.dropFirst()
if arguments.contains("--status") {
    printStatus()
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
    fputs("알 수 없는 옵션: \(unknown)\n--help 를 참고하세요.\n", stderr)
    exit(1)
}

let term = Terminal.shared
term.setup()

// Query the terminal theme before the main loop so the OSC reply
// can't be mistaken for keystrokes.
let terminalDark = term.backgroundIsDark()

let initialSize = term.size
let world = World(cols: initialSize.cols, rows: initialSize.rows,
                  terminalDark: terminalDark, restoring: SaveStore.load())

func shutdown() -> Never {
    world.writeSave()
    Terminal.shared.teardown()
    print("어항을 저장했어요. 다음에 또 만나요! ><>  <><")
    exit(0)
}

// Registered after `world` exists — the handlers reference it via shutdown().
signal(SIGINT) { _ in shutdown() }
signal(SIGTERM) { _ in shutdown() }

let frameMicroseconds: UInt32 = 80_000 // ~12.5 fps, plenty for a calm tank

mainLoop: while true {
    let (cols, rows) = term.size
    if cols != world.cols || rows != world.rows {
        world.resize(cols: cols, rows: rows)
    }

    for event in term.readEvents() {
        switch event {
        case .key(let key):
            switch key {
            case "f", "F":
                world.feed()
            case "g", "G":
                world.feedLive()
            case "n", "N":
                world.toggleLighting()
            case "i", "I":
                world.toggleRoster()
            case "m", "M":
                world.toggleMusic()
            case "q", "Q":
                break mainLoop
            default:
                break
            }
        case .click(let col, let row):
            world.touch(col: col, row: row)
        }
    }

    world.update()
    fputs(world.render(), stdout)
    fflush(stdout)
    usleep(frameMicroseconds)
}

shutdown()
