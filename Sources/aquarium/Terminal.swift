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

    /// Asks the terminal for its background color via OSC 11.
    /// Returns nil when the terminal doesn't reply (e.g. piped stdin, old emulators).
    /// Call before the main loop starts so the reply can't be mistaken for keystrokes.
    func backgroundIsDark() -> Bool? {
        guard rawEnabled else { return nil }
        fputs("\u{1B}]11;?\u{07}", stdout)
        fflush(stdout)

        var bytes: [UInt8] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        while ProcessInfo.processInfo.systemUptime < deadline {
            var chunk = [UInt8](repeating: 0, count: 64)
            let n = read(STDIN_FILENO, &chunk, chunk.count)
            if n > 0 {
                bytes.append(contentsOf: chunk[0..<n])
                // Reply ends with BEL or ST (ESC \)
                if bytes.contains(7) || Array(bytes.suffix(2)) == [0x1B, 0x5C] { break }
            } else {
                usleep(10_000)
            }
        }

        guard let reply = String(bytes: bytes, encoding: .utf8),
              let start = reply.range(of: "rgb:") else { return nil }
        let channels = reply[start.upperBound...]
            .split(separator: "/")
            .prefix(3)
            .map { component -> Double in
                let hex = component.prefix { $0.isHexDigit }
                guard !hex.isEmpty, let value = UInt32(String(hex), radix: 16) else { return 0 }
                return Double(value) / (pow(16, Double(hex.count)) - 1)
            }
        guard channels.count == 3 else { return nil }
        let luminance = 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        return luminance < 0.5
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
