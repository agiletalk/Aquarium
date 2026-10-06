import AppKit

/// 화면 테마 — 배경색과, 터미널 256색 인덱스를 실제 색으로 옮기는 규칙.
/// ASCII는 그대로 두고 색만 바꾼다(그래픽 에셋 없음).
enum Theme: String, CaseIterable {
    /// 딥 네이비 배경 + xterm 256색 그대로. `aquarium --card` PNG와 같은 바탕.
    case standard
    /// 연한 하늘색 배경. 색조는 두고 밝기만 배경과 대비되게 낮춘다.
    case light
    /// 조명이 낮이면 light, 밤이면 standard.
    case automatic
    /// 검정 배경 + 녹색 단색(원래 색의 밝기를 녹색 단계로).
    case crt
    /// 검정 배경 + 호박색 단색.
    case amber

    /// 지금 실제로 칠할 테마 — automatic만 조명에 따라 갈린다.
    func resolved(isNight: Bool) -> Theme {
        self == .automatic ? (isNight ? .standard : .light) : self
    }
}

/// 렌더러가 읽는 현재 색. 테마가 바뀌면 컨트롤러가 apply 후 렌더러를 새로 만든다.
enum Palette {
    private(set) static var theme: Theme = .standard
    private(set) static var background = backgroundColor(for: .standard)
    private(set) static var colors: [CGColor] = colorTable(for: .standard)

    static func apply(_ theme: Theme) {
        guard theme != self.theme else { return }
        self.theme = theme
        background = backgroundColor(for: theme)
        colors = colorTable(for: theme)
    }

    private static func backgroundColor(for theme: Theme) -> CGColor {
        switch theme {
        case .standard, .automatic: return CGColor(srgbRed: 0.078, green: 0.086, blue: 0.13, alpha: 1)
        case .light: return CGColor(srgbRed: 0.91, green: 0.955, blue: 0.97, alpha: 1)
        case .crt: return CGColor(srgbRed: 0.02, green: 0.04, blue: 0.025, alpha: 1)
        case .amber: return CGColor(srgbRed: 0.045, green: 0.03, blue: 0.015, alpha: 1)
        }
    }

    private static func colorTable(for theme: Theme) -> [CGColor] {
        (0...255).map { index in
            let (r, g, b) = xterm(UInt8(index))
            let (r2, g2, b2) = transform(r, g, b, theme)
            return CGColor(srgbRed: r2, green: g2, blue: b2, alpha: 1)
        }
    }

    private static func transform(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                                  _ theme: Theme) -> (CGFloat, CGFloat, CGFloat) {
        // 지각 밝기(대략). 단색 테마의 밝기 단계와 밝은 테마의 대비 판정에 쓴다.
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        switch theme {
        case .standard, .automatic:
            return (r, g, b)
        case .light:
            // 밝은 배경에서 노랑·흰색이 사라지지 않게, 밝기가 0.45를 넘으면 그 비율만큼 낮춘다.
            // 색조는 그대로라 물고기 색 구분이 유지된다. 아주 어두운 색은 그대로 둔다.
            let cap: CGFloat = 0.45
            guard luma > cap else { return (r, g, b) }
            let k = cap / luma
            return (r * k, g * k, b * k)
        case .crt:
            // 색조 140°±55°(노란 연두 ~ 녹색 ~ 청록) 안에 원래 색조를 눌러 담는다 — 단색이면
            // 밝기가 비슷한 물고기끼리 구분이 안 됐다. 무채색은 녹색 단색 그대로.
            return phosphor(r, g, b, luma: luma, center: 140, spread: 55,
                            mono: { l in (0.18 * l, l, 0.28 * l) })
        case .amber:
            // 색조 35°±28°(붉은 주황 ~ 호박 ~ 노랑).
            return phosphor(r, g, b, luma: luma, center: 35, spread: 28,
                            mono: { l in (l, 0.64 * l, 0.12 * l) })
        }
    }

    /// 형광관 테마 — 무채색은 단색 밝기 단계, 유채색은 색조를 [center-spread, center+spread]로
    /// 옮긴다. 원래 색조 순서(빨강→노랑→초록→파랑→보라)가 범위 안에서 그대로 유지된다.
    private static func phosphor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, luma: CGFloat,
                                 center: CGFloat, spread: CGFloat,
                                 mono: (CGFloat) -> (CGFloat, CGFloat, CGFloat)) -> (CGFloat, CGFloat, CGFloat) {
        // 바닥 밝기를 둬서 어두운 색(밤 감광 포함)도 검정에 묻히지 않게 한다.
        let level = 0.22 + 0.78 * luma
        let maxC = max(r, g, b), minC = min(r, g, b)
        let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
        guard saturation > 0.2 else { return mono(level) }
        var hue: CGFloat
        if maxC == r { hue = (g - b) / (maxC - minC) }
        else if maxC == g { hue = 2 + (b - r) / (maxC - minC) }
        else { hue = 4 + (r - g) / (maxC - minC) }
        hue = (hue * 60).truncatingRemainder(dividingBy: 360)
        if hue < 0 { hue += 360 }
        let mapped = center - spread + hue / 360 * spread * 2
        // 밝기는 원래 밝기 단계를 따르되 유채색은 조금 더 밝게 — 형광 느낌.
        return hsv(mapped, 0.78, min(1, 0.35 + 0.75 * maxC))
    }

    private static func hsv(_ h: CGFloat, _ s: CGFloat, _ v: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let c = v * s, hp = (h / 60).truncatingRemainder(dividingBy: 6)
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch hp {
        case ..<1: (r, g, b) = (c, x, 0)
        case ..<2: (r, g, b) = (x, c, 0)
        case ..<3: (r, g, b) = (0, c, x)
        case ..<4: (r, g, b) = (0, x, c)
        case ..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    /// xterm 256색 — `aquarium --card`(Card.rgb)와 같은 공식.
    private static func xterm(_ index: UInt8) -> (CGFloat, CGFloat, CGFloat) {
        switch index {
        case 0...15:
            let base: [(CGFloat, CGFloat, CGFloat)] = [
                (0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0),
                (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
                (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0),
                (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
            ]
            let (r, g, b) = base[Int(index)]
            return (r / 255, g / 255, b / 255)
        case 16...231:
            let i = Int(index) - 16
            let steps: [CGFloat] = [0, 95, 135, 175, 215, 255].map { $0 / 255 }
            return (steps[i / 36], steps[(i % 36) / 6], steps[i % 6])
        default:
            let v = CGFloat(8 + 10 * (Int(index) - 232)) / 255
            return (v, v, v)
        }
    }
}
