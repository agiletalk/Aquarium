import Foundation

let appVersion = "2.8.0"

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

    world.update()
    fputs(world.render(), stdout)
    fflush(stdout)
    usleep(frameMicroseconds)
}

shutdown()
