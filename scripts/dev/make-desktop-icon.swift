// Aquarium Desktop 앱 아이콘 생성기 — 그래픽 에셋 없이 코드로 그린다.
//
//   swift scripts/dev/make-desktop-icon.swift [출력 폴더]
//
// 기본 출력: Desktop/AquariumDesktop/Assets.xcassets/AppIcon.appiconset
// 콘셉트: 어항 속 ASCII 물고기. 앱이 실제로 쓰는 문자 물고기 `><(((°>`가 주인공이다.
// macOS 아이콘 그리드(1024 캔버스, 824 본체, 100 여백)를 따르고, 작은 크기는 단순화한다.
import AppKit
import CoreText

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let corner: CGFloat = 185
/// 지금 그리는 크기 ÷ 1024. CG의 그림자 흐림·오프셋은 좌표 변환(CTM)을 따르지 않아 직접 곱한다 —
/// 안 곱하면 작은 아이콘에서 그림자가 캔버스 밖으로 번졌다가 잘려 네모난 상자가 비친다.
var pixelScale: CGFloat = 1

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func monoFont(_ size: CGFloat, weight: NSFont.Weight = .bold) -> CTFont {
    NSFont.monospacedSystemFont(ofSize: size, weight: weight) as CTFont
}

/// 문자열 한 줄을 글자별 색으로 그린다. origin은 기준선 왼쪽.
func drawText(_ ctx: CGContext, _ text: String, font: CTFont, at origin: CGPoint,
              colors: [CGColor], glow: CGColor? = nil, glowBlur: CGFloat = 0, tracking: CGFloat = 1) {
    ctx.saveGState()
    if let glow { ctx.setShadow(offset: .zero, blur: glowBlur * pixelScale, color: glow) }
    var x = origin.x
    for (i, ch) in text.enumerated() {
        let attr = NSAttributedString(string: String(ch), attributes: [
            .font: font, .foregroundColor: NSColor(cgColor: colors[min(i, colors.count - 1)])!,
        ])
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: x, y: origin.y)
        CTLineDraw(line, ctx)
        x += CTLineGetTypographicBounds(line, nil, nil, nil) * tracking
    }
    ctx.restoreGState()
}

/// tracking: 글자 간격 배율. 고정폭 그대로면 `> < ( ( (`처럼 흩어져 한 마리로 안 읽힌다.
func textWidth(_ text: String, font: CTFont, tracking: CGFloat = 1) -> CGFloat {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    let advance = CTLineGetTypographicBounds(line, nil, nil, nil) / CGFloat(text.count)
    return advance * tracking * CGFloat(text.count - 1) + advance
}

/// 가운데 정렬로 한 줄.
func drawCentered(_ ctx: CGContext, _ text: String, font: CTFont, y: CGFloat, colors: [CGColor],
                  tracking: CGFloat = 1, glow: CGColor? = nil, glowBlur: CGFloat = 0) {
    let w = textWidth(text, font: font, tracking: tracking)
    drawText(ctx, text, font: font, at: CGPoint(x: 512 - w / 2, y: y), colors: colors,
             glow: glow, glowBlur: glowBlur, tracking: tracking)
}

/// detail: 0 = 물고기만(16·32px), 1 = 물고기+방울(64px), 2 = 전부(128px 이상)
func render(pixels: Int, detail: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(pixels) / canvas
    pixelScale = s
    ctx.scaleBy(x: s, y: s)
    ctx.setShouldSmoothFonts(false)

    let squircle = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // 본체 그림자 — macOS 아이콘처럼 살짝 떠 있게.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: srgb(0x000000, 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(srgb(0x0A1A33))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // 바다: 수면의 청록 → 앱 배경과 같은 딥 네이비.
    let sea = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                         colors: [srgb(0x2A8FB8), srgb(0x15507E), srgb(0x0D2547), srgb(0x14162A)] as CFArray,
                         locations: [0, 0.38, 0.72, 1])!
    ctx.drawLinearGradient(sea, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
    // 수면에서 들어오는 빛.
    let light = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [srgb(0xBFF4FF, 0.38), srgb(0xBFF4FF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(light, startCenter: CGPoint(x: 430, y: body.maxY + 40), startRadius: 0,
                           endCenter: CGPoint(x: 430, y: body.maxY + 40), endRadius: 560, options: [])
    if detail >= 2 {
        // 수면에서 비스듬히 내려오는 옅은 빛줄기 — 깊이감만, 눈에 띄지 않게.
        for (top, width, alpha) in [(300.0, 70.0, 0.07), (470.0, 110.0, 0.05), (640.0, 60.0, 0.06)] {
            ctx.saveGState()
            ctx.move(to: CGPoint(x: top, y: body.maxY))
            ctx.addLine(to: CGPoint(x: top + width, y: body.maxY))
            ctx.addLine(to: CGPoint(x: top + width - 220, y: body.minY + 160))
            ctx.addLine(to: CGPoint(x: top - 260, y: body.minY + 160))
            ctx.closePath()
            ctx.clip()
            let ray = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: [srgb(0xE6FBFF, alpha), srgb(0xE6FBFF, 0)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(ray, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY + 160), options: [])
            ctx.restoreGState()
        }
    }

    if detail >= 2 {
        // 수면 — ASCII 물결이 폭 전체로.
        drawCentered(ctx, "~^~~~^~~^~~~^~~^~~~^~~^~", font: monoFont(44, weight: .bold), y: 818,
                     colors: [srgb(0xA8F0FF, 0.5)], tracking: 0.98)
        // 뒤쪽의 작은 물고기 — 왼쪽으로 헤엄치는 청록. 멀리 있어 흐리다.
        drawText(ctx, "<°)))><", font: monoFont(62, weight: .bold), at: CGPoint(x: 212, y: 676),
                 colors: [srgb(0x74E6DA, 0.78)], glow: srgb(0x4FD1C5, 0.3), glowBlur: 10, tracking: 0.86)
        // 모래 바닥과, 그 위에서 자라는 해초.
        drawCentered(ctx, "._.:._.:._.:._.:._.:._.:._", font: monoFont(42, weight: .bold), y: 150,
                     colors: [srgb(0xD8B98A, 0.82)], tracking: 1)
        let weedFont = monoFont(56, weight: .bold)
        for (x, stems, alpha) in [(176.0, [")", "(", ")"], 0.92), (236.0, ["(", ")"], 0.66),
                                  (792.0, ["(", ")", "("], 0.88), (732.0, [")", "("], 0.6)] {
            for (k, ch) in stems.enumerated() {
                drawText(ctx, ch, font: weedFont, at: CGPoint(x: x + (k % 2 == 0 ? 0 : 9), y: 204 + CGFloat(k) * 54),
                         colors: [srgb(0x5BD16B, alpha)])
            }
        }
    }

    // 주인공 물고기 — 글자별 색: 꼬리 산호, 몸통 호박, 눈 흰색, 입 호박.
    let fish = "><(((°>"
    let tracking: CGFloat = 0.8
    let fishSize: CGFloat = detail == 0 ? 205 : 172
    let fishFont = monoFont(fishSize, weight: .heavy)
    let fishW = textWidth(fish, font: fishFont, tracking: tracking)
    let fishY: CGFloat = detail == 0 ? 445 : 452
    let fishX = 512 - fishW / 2 - (detail == 0 ? 0 : 22)
    let tail = srgb(0xFF6F61), bodyC = srgb(0xFFB547), belly = srgb(0xFFC96B), eye = srgb(0xFFFFFF), mouth = srgb(0xFFD27F)
    drawText(ctx, fish, font: fishFont, at: CGPoint(x: fishX, y: fishY),
             colors: [tail, tail, bodyC, belly, bodyC, eye, mouth],
             glow: srgb(0xFF9A3C, 0.7), glowBlur: detail == 0 ? 16 : 30, tracking: tracking)

    if detail >= 1 {
        // 입 앞에서 올라가는 공기방울 — 위로 갈수록 커진다.
        let bubble = srgb(0xD6F7FF, 0.92)
        let mouthX = fishX + fishW
        drawText(ctx, "°", font: monoFont(70, weight: .bold), at: CGPoint(x: mouthX - 6, y: fishY + 112),
                 colors: [bubble.copy(alpha: 0.85)!])
        drawText(ctx, "o", font: monoFont(60, weight: .regular), at: CGPoint(x: mouthX + 16, y: fishY + 182),
                 colors: [bubble], glow: srgb(0x9BEBFF, 0.55), glowBlur: 8)
        drawText(ctx, "o", font: monoFont(86, weight: .light), at: CGPoint(x: mouthX - 18, y: fishY + 262),
                 colors: [bubble], glow: srgb(0x9BEBFF, 0.55), glowBlur: 12)
    }

    // 유리 같은 안쪽 테두리 — 어두운 배경에서도 윤곽이 보이게.
    ctx.restoreGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(srgb(0xFFFFFF, 0.14))
    ctx.setLineWidth(3)
    ctx.strokePath()
    return ctx.makeImage()!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let out = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("Desktop/AquariumDesktop/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// macOS 앱 아이콘 슬롯: (포인트, 배율)
let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in slots {
    let px = points * scale
    let detail = px <= 32 ? 0 : px <= 64 ? 1 : 2
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let data = NSBitmapImageRep(cgImage: render(pixels: px, detail: detail)).representation(using: .png, properties: [:])!
    try data.write(to: out.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))
let catalog = out.deletingLastPathComponent().appendingPathComponent("Contents.json")
if !FileManager.default.fileExists(atPath: catalog.path) {
    try #"{"info":{"author":"xcode","version":1}}"#.data(using: .utf8)!.write(to: catalog)
}
print("아이콘 \(images.count)장 → \(out.path)")
