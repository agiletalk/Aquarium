import AppKit

/// 어항 사진 — 화면 캡처가 아니라 지금 셀 상태를 처음부터 다시 그린다.
/// 바탕화면 아이콘·위젯·다른 창이 끼어들 수 없고, 렌더러(CPU·GPU)와 무관하게 같은 그림이 나온다.
enum TankPhoto {
    /// 상태줄을 뺀 수조를 배경색 여백과 함께 PNG로. 열린 패널은 화면에 보이는 그대로 담긴다.
    static func png(of frame: CellFrame, scale: CGFloat) -> Data? {
        let tankRows = frame.rows - 1 // 마지막 행은 상태줄
        guard tankRows > 0 else { return nil }
        let margin = frame.metrics.height
        let tankSize = CGSize(width: CGFloat(frame.cols) * frame.metrics.width,
                              height: CGFloat(tankRows) * frame.metrics.height)
        let canvas = CGSize(width: tankSize.width + margin * 2, height: tankSize.height + margin * 2)
        let width = Int((canvas.width * scale).rounded(.up))
        let height = Int((canvas.height * scale).rounded(.up))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setShouldSmoothFonts(false)
        context.setFillColor(Palette.background)
        context.fill(CGRect(origin: .zero, size: canvas))

        // 그리드는 상태줄까지 rows행 — 상태줄이 아래 여백으로 내려가도록 한 행만큼 내려 그리고 수조 영역으로 자른다.
        context.clip(to: CGRect(origin: CGPoint(x: margin, y: margin), size: tankSize))
        context.translateBy(x: margin, y: margin - frame.metrics.height)
        var batch = GlyphBatch()
        for r in 0..<tankRows {
            for c in 0..<frame.cols {
                frame.addGlyph(frame.cells[r * frame.cols + c], row: r, col: c, to: &batch)
            }
        }
        batch.draw(in: context)

        guard let image = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = canvas // 레티나에서 2배로 커 보이지 않게 포인트 크기를 적어 둔다
        return rep.representation(using: .png, properties: [:])
    }

    /// macOS 스크린샷 셔터음. 시스템 파일이 없으면 조용히 넘어간다.
    static func playShutter() {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        NSSound(contentsOfFile: path, byReference: true)?.play()
    }
}
