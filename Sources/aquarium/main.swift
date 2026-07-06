import Foundation

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
            case "n", "N":
                world.toggleLighting()
            case "i", "I":
                world.toggleRoster()
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
