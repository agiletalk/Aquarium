import AppKit

/// 터미널 256색 인덱스 → 색. `aquarium --card`(Card.rgb)와 같은 xterm 공식이다.
enum Palette {
    /// 바탕 — `--card` PNG와 같은 딥 네이비.
    static let background = CGColor(srgbRed: 0.078, green: 0.086, blue: 0.13, alpha: 1)

    static let colors: [CGColor] = (0...255).map { color(UInt8($0)) }

    private static func color(_ index: UInt8) -> CGColor {
        switch index {
        case 0...15:
            // xterm 기본 16색
            let base: [(CGFloat, CGFloat, CGFloat)] = [
                (0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0),
                (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
                (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0),
                (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
            ]
            let (r, g, b) = base[Int(index)]
            return CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
        case 16...231:
            let i = Int(index) - 16
            let steps: [CGFloat] = [0, 95, 135, 175, 215, 255].map { $0 / 255 }
            return CGColor(srgbRed: steps[i / 36], green: steps[(i % 36) / 6], blue: steps[i % 6], alpha: 1)
        default:
            let v = CGFloat(8 + 10 * (Int(index) - 232)) / 255
            return CGColor(srgbRed: v, green: v, blue: v, alpha: 1)
        }
    }
}
