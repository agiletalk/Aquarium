import Foundation

func shutdown() -> Never {
    Terminal.shared.teardown()
    print("오늘도 평화로운 어항이었습니다. ><>  <><")
    exit(0)
}

signal(SIGINT) { _ in shutdown() }
signal(SIGTERM) { _ in shutdown() }

let term = Terminal.shared
term.setup()

let initialSize = term.size
let world = World(cols: initialSize.cols, rows: initialSize.rows)

let frameMicroseconds: UInt32 = 80_000 // ~12.5 fps, plenty for a calm tank

mainLoop: while true {
    let (cols, rows) = term.size
    if cols != world.cols || rows != world.rows {
        world.resize(cols: cols, rows: rows)
    }

    for key in term.readKeys() {
        switch key {
        case "f", "F":
            world.feed()
        case "q", "Q":
            break mainLoop
        default:
            break
        }
    }

    world.update()
    fputs(world.render(), stdout)
    fflush(stdout)
    usleep(frameMicroseconds)
}

shutdown()
