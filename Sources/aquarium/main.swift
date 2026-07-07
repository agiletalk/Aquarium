import Foundation

let appVersion = "2.2.0"

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

if arguments.contains("--status") {
    printStatus()
    exit(0)
}
if arguments.contains("--card") {
    Card.generate()
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

let term = Terminal.shared
term.setup()

// Query the terminal theme before the main loop so the OSC reply
// can't be mistaken for keystrokes.
let terminalDark = term.backgroundIsDark()

let initialSize = term.size
let world = World(cols: initialSize.cols, rows: initialSize.rows,
                  terminalDark: terminalDark, restoring: SaveStore.load())
if let focusMinutes {
    world.startFocus(minutes: focusMinutes)
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

    world.update()
    fputs(world.render(), stdout)
    fflush(stdout)
    usleep(frameMicroseconds)
}

shutdown()
