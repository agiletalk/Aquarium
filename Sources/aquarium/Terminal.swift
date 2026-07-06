import Foundation

enum InputEvent {
    case key(Character)
    case click(col: Int, row: Int) // 0-based grid coordinates
}

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
        // ?1000h/?1006h: report mouse clicks as SGR escape sequences
        fputs(ANSI.altScreenOn + ANSI.hideCursor + ANSI.wrapOff
              + "\u{1B}[?1000h\u{1B}[?1006h" + ANSI.clear, stdout)
        fflush(stdout)
    }

    func teardown() {
        fputs("\u{1B}[?1006l\u{1B}[?1000l"
              + ANSI.reset + ANSI.wrapOn + ANSI.altScreenOff + ANSI.showCursor, stdout)
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

    private var pending: [UInt8] = []

    /// Reads plain keys plus SGR mouse clicks (ESC [ < b ; col ; row M).
    /// Incomplete escape sequences are kept for the next call.
    func readEvents() -> [InputEvent] {
        var chunk = [UInt8](repeating: 0, count: 128)
        let n = read(STDIN_FILENO, &chunk, chunk.count)
        if n > 0 { pending.append(contentsOf: chunk[0..<n]) }
        guard !pending.isEmpty else { return [] }

        var events: [InputEvent] = []
        let buf = pending
        var i = 0
        var incomplete = false

        while i < buf.count {
            if buf[i] == 0x1B {
                guard i + 1 < buf.count else { incomplete = true; break }
                guard buf[i + 1] == UInt8(ascii: "[") else { i += 1; continue }
                // CSI sequence: parameters, then a final byte in 0x40...0x7E
                var j = i + 2
                while j < buf.count, !(0x40...0x7E).contains(buf[j]) { j += 1 }
                guard j < buf.count else { incomplete = true; break }
                if i + 2 < j, buf[i + 2] == UInt8(ascii: "<"), buf[j] == UInt8(ascii: "M") {
                    let body = String(bytes: buf[(i + 3)..<j], encoding: .utf8) ?? ""
                    let parts = body.split(separator: ";").compactMap { Int($0) }
                    if parts.count == 3, parts[0] == 0 { // left button press
                        events.append(.click(col: parts[1] - 1, row: parts[2] - 1))
                    }
                }
                i = j + 1
                continue
            }
            if buf[i] >= 0x20, buf[i] < 0x7F {
                events.append(.key(Character(UnicodeScalar(buf[i]))))
            }
            i += 1
        }

        pending = incomplete ? Array(buf[i...]) : []
        return events
    }

    var size: (cols: Int, rows: Int) {
        var w = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ_DARWIN, &w) == 0, w.ws_col > 0, w.ws_row > 0 {
            return (Int(w.ws_col), Int(w.ws_row))
        }
        return (80, 24)
    }
}
