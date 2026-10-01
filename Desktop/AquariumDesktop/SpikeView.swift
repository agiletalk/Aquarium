import AppKit
import AquariumCore

/// 창 동작 확인용 — 단색 배경, 테스트 문자열, visibleFrame 경계.
/// Step 3에서 Core Text 렌더러로 교체한다.
final class SpikeView: NSView {
    private let screenFrame: NSRect
    private let visibleFrame: NSRect
    private let index: Int

    init(screen: NSScreen, index: Int) {
        screenFrame = screen.frame
        visibleFrame = screen.visibleFrame
        self.index = index
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.18, alpha: 1).setFill()
        bounds.fill()

        // visibleFrame(메뉴바·Dock 제외 영역)을 창 좌표로 — 수조 그리드가 들어갈 자리.
        let visible = visibleFrame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        NSColor.systemTeal.setStroke()
        let path = NSBezierPath(rect: visible.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        path.stroke()

        let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let lines = [
            "><(((°>   Aquarium Desktop — wallpaper spike   <°)))><",
            "screen \(index)  frame \(Int(screenFrame.width))x\(Int(screenFrame.height))"
                + "  visible \(Int(visibleFrame.width))x\(Int(visibleFrame.height))",
            "AquariumCore 링크 확인: displayWidth(\"물고기\") = \(TextWidth.displayWidth("물고기"))",
        ]
        let lineHeight = font.ascender - font.descender + font.leading + 6
        var y = visible.midY + lineHeight
        for line in lines {
            let text = NSAttributedString(string: line, attributes: attrs)
            text.draw(at: NSPoint(x: visible.midX - text.size().width / 2, y: y))
            y -= lineHeight
        }
    }
}
