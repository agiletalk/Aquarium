import Foundation

enum ANSI {
    static let home = "\u{1B}[H"
    static let clear = "\u{1B}[2J"
    static let reset = "\u{1B}[0m"
    static let hideCursor = "\u{1B}[?25l"
    static let showCursor = "\u{1B}[?25h"
    static let altScreenOn = "\u{1B}[?1049h"
    static let altScreenOff = "\u{1B}[?1049l"
    static let wrapOff = "\u{1B}[?7l"
    static let wrapOn = "\u{1B}[?7h"

    static func fg(_ color: UInt8) -> String { "\u{1B}[38;5;\(color)m" }
}

final class Terminal {
    static let shared = Terminal()

    private var original = termios()
    private var rawEnabled = false

    // TIOCGWINSZ is a function-like macro, so it isn't imported into Swift.
    private let TIOCGWINSZ_DARWIN: UInt = 0x4008_7468

    func setup() {
        if isatty(STDIN_FILENO) == 1, tcgetattr(STDIN_FILENO, &original) == 0 {
            var raw = original
            raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
            raw.c_cc.16 = 0 // VMIN:  read() returns immediately...
            raw.c_cc.17 = 0 // VTIME: ...even when no bytes are available
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
            rawEnabled = true
        }
        fputs(ANSI.altScreenOn + ANSI.hideCursor + ANSI.wrapOff + ANSI.clear, stdout)
        fflush(stdout)
    }

    func teardown() {
        fputs(ANSI.reset + ANSI.wrapOn + ANSI.altScreenOff + ANSI.showCursor, stdout)
        fflush(stdout)
        if rawEnabled {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            rawEnabled = false
        }
    }

    func readKeys() -> [Character] {
        var buf = [UInt8](repeating: 0, count: 16)
        let n = read(STDIN_FILENO, &buf, buf.count)
        guard n > 0 else { return [] }
        return buf[0..<n].map { Character(UnicodeScalar($0)) }
    }

    var size: (cols: Int, rows: Int) {
        var w = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ_DARWIN, &w) == 0, w.ws_col > 0, w.ws_row > 0 {
            return (Int(w.ws_col), Int(w.ws_row))
        }
        return (80, 24)
    }
}
