import AppKit
import AquariumCore
import CoreText
import IOSurface

/// CPU 렌더러 — 한 화면의 어항을 Core Text 글리프로 IOSurface에 그린다 (render 층).
/// GPU 렌더러는 MetalTankView. 어느 쪽을 쓸지는 Settings.gpuRendering.
/// 셀 크기 = 모노스페이스 글리프 advance × line height. 뷰는 그리드 크기만큼만 만들고
/// (가장자리·메뉴바·Dock 뒤는 창 배경색), 매 tick **바뀐 셀만** 다시 그린다.
///
/// 측정으로 정한 구조다 (Release, 내장 Retina 한 화면, 30초 평균 CPU):
/// - layer-backed NSView 전체 다시 그리기: 4.6%. AppKit이 그리기를 CA 디스플레이
///   리스트로 기록하고, XDR에서 백킹이 16비트 부동소수점으로 잡혀 IOSurface 183MB.
/// - 같은 뷰에 바뀐 셀 구간만 무효화: 43%. 커밋 때 글리프 외곽선을 사각형마다 다시 계산.
/// - CALayer 하나에 부분 무효화: 7.9%. CA가 사각형을 합집합 하나로 합치고 이전 버퍼를 복사.
/// - 행 × 16칸 타일 레이어 1,000여 개: 5.1%. 프레임당 바뀌는 셀은 평균 133개인데
///   타일 단위로 약 1,000칸을 칠하고, 레이어 수만큼 커밋 비용이 든다.
/// - 그래서 IOSurface 두 장에 직접 그리고 번갈아 레이어 contents로 건넨다. 바뀐 셀만
///   칠하고, CA에는 레이어 하나만 넘어간다: 3.8~4.2%.
/// - 계측해 보니 그중 절반이 배경 지우기였고, 비용은 쓰는 바이트가 아니라 WindowServer가
///   합성한 버퍼의 페이지에 **처음 닿는 횟수**에 비례했다(같은 영역 두 번째 지우기는 6.6배
///   빠름, 픽셀 행 1개 ≈ 16KB 페이지 1개). 그래서 닿는 행 수를 줄인다 — 버퍼마다 실제로
///   그려진 셀을 따로 들고 그 버퍼와 다른 셀만 칠하고, 빈칸이던 셀은 지우지 않으며,
///   셀을 픽셀 행 우선으로 훑는다.
final class TankView: NSView, TankRenderer {
    let cells: CellFrame
    weak var world: World?

    private var metrics: CellMetrics { cells.metrics }
    private var glyphs: GlyphCache { cells.glyphs }
    /// 버퍼마다 실제로 그려져 있는 셀. 뒤 버퍼는 이것과 cells가 다른 셀만 칠한다.
    private var drawn: [[DrawnCell]] = []
    private var buffers: [SurfaceBuffer] = []
    private var front = 0
    private var scale: CGFloat = 0
    /// 셀 한 칸의 픽셀 높이 (줄 높이는 정수 포인트라 배율을 곱해도 정수).
    private var cellPixelHeight = 0

    init(visibleRect: CGRect, metrics: CellMetrics) {
        let grid = Self.gridFrame(in: visibleRect, metrics: metrics)
        cells = CellFrame(cols: grid.cols, rows: grid.rows, metrics: metrics)
        super.init(frame: grid.frame)

        let host = CALayer()
        host.backgroundColor = Palette.background
        host.isOpaque = true
        host.contentsGravity = .resize
        host.actions = ["contents": NSNull()]
        layer = host      // wantsLayer보다 먼저 — layer-hosting
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { true }

    /// 화면 배율에 맞춰 버퍼를 만든다. 창에 붙은 뒤에야 배율을 안다.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        guard scale != self.scale else { return }
        self.scale = scale
        cellPixelHeight = Int((metrics.height * scale).rounded())
        Probe.cellPixelWidth = Double(metrics.width * scale)
        Probe.cellPixelHeight = cellPixelHeight
        layer?.contentsScale = scale
        buffers = (0..<2).compactMap { _ in SurfaceBuffer(size: bounds.size, scale: scale) }
        // 새 버퍼는 배경색으로 칠해져 있다 = 전부 빈칸.
        drawn = buffers.map { _ in Array(repeating: DrawnCell(), count: cols * rows) }
        guard buffers.count == 2 else { return }
        front = 0
        paint(into: 0)
        present()
    }

    /// 이번 tick의 상태를 셀로 펼치고, 뒤 버퍼에서 다른 셀만 칠해 앞으로 돌린다.
    func refresh() {
        guard let world else { return }
        let tf = Probe.now()
        cells.update(from: world)
        Probe.add("compose+flatten", since: tf)

        guard buffers.count == 2 else { return }
        let back = 1 - front
        let tp = Probe.now()
        let painted = paint(into: back)
        Probe.add("paint(total)", since: tp, count: painted)
        guard painted > 0 else { return }   // 바뀐 게 없으면 버퍼를 돌리지 않는다
        front = back
        let tpr = Probe.now()
        present()
        Probe.add("present", since: tpr)
        if Probe.enabled { Probe.verifyTick { self.verifyFront() } }
    }

    private func present() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = buffers[front].surface
        CATransaction.commit()
    }

    /// 버퍼 b에서 cells와 다른 셀을 칠하고, 칠한 셀 수를 돌려준다.
    @discardableResult
    private func paint(into b: Int) -> Int {
        let buffer = buffers[b]
        let statusBase = (rows - 1) * cols
        let cellPixelWidth = metrics.width * scale
        var clears: [PixelRect] = []
        var batch = GlyphBatch()
        var count = 0

        let pixelHeight = buffer.pixelHeight
        /// 지울 영역 — 셀 전체가 아니라 그 버퍼에 있던 글자의 잉크 영역(±1px)만.
        /// 닿는 픽셀 행 수가 곧 비용이라('.'은 36행 대신 4~5행) 가장 큰 절감이다.
        /// 글자는 행 띠로 잘려 그려지고 셀 폭은 정수 픽셀이라 잉크는 셀 밖으로 안 나간다.
        func clearRect(_ old: DrawnCell, _ r: Int, _ c: Int) -> PixelRect {
            let cell = PixelRect(x0: Int((CGFloat(c) * cellPixelWidth).rounded()),
                                 x1: Int((CGFloat(c + 1) * cellPixelWidth).rounded()),
                                 y0: r * cellPixelHeight, y1: (r + 1) * cellPixelHeight, row: r)
            let glyph = cells.glyph(for: old)
            guard !old.wide, !glyph.ink.isNull, !glyph.ink.isEmpty else { return cell }
            let originX = CGFloat(c) * metrics.width
            let originY = bounds.height - CGFloat(r + 1) * metrics.height + metrics.descent
            let ink = glyph.ink.offsetBy(dx: originX, dy: originY)
            return PixelRect(x0: max(cell.x0, Int((ink.minX * scale).rounded(.down)) - 1),
                             x1: min(cell.x1, Int((ink.maxX * scale).rounded(.up)) + 1),
                             y0: max(cell.y0, pixelHeight - Int((ink.maxY * scale).rounded(.up)) - 1),
                             y1: min(cell.y1, pixelHeight - Int((ink.minY * scale).rounded(.down)) + 1),
                             row: r)
        }
        func addGlyph(_ cell: DrawnCell, _ r: Int, _ c: Int) {
            cells.addGlyph(cell, row: r, col: c, to: &batch)
        }

        // 수조 그리드: 다른 셀만. 그 버퍼에서 빈칸이던 셀은 이미 배경색이라 지우지 않는다.
        for i in 0..<statusBase where drawn[b][i] != cells.cells[i] {
            let r = i / cols, c = i % cols
            if !drawn[b][i].isBlank { clears.append(clearRect(drawn[b][i], r, c)) }
            addGlyph(cells.cells[i], r, c)
            drawn[b][i] = cells.cells[i]
            count += 1
        }
        // 상태줄은 2칸 글자가 섞여 셀 단위로는 옆 칸에 번진 잉크가 남는다 — 바뀌면 줄 전체.
        if (statusBase..<(rows * cols)).contains(where: { drawn[b][$0] != cells.cells[$0] }) {
            clears.append(PixelRect(x0: 0, x1: buffer.pixelWidth,
                                    y0: (rows - 1) * cellPixelHeight, y1: rows * cellPixelHeight, row: rows - 1))
            for c in 0..<cols {
                addGlyph(cells.cells[statusBase + c], rows - 1, c)
                drawn[b][statusBase + c] = cells.cells[statusBase + c]
            }
            count += cols
        }
        guard count > 0 else { return 0 }

        buffer.draw { context in
            let tcl = Probe.now()
            // 배경은 CG를 거치지 않고 픽셀에 직접 쓴다. 셀마다 fill을 부르면 호출당 고정
            // 비용이 렌더 시간의 절반이었고, fill([CGRect])는 영역 합집합 계산으로 더 느렸다.
            buffer.clear(clears)
            Probe.add("  clear", since: tcl, count: clears.count)
            let tg = Probe.now()
            batch.draw(in: context)
            Probe.add("  glyphs", since: tg)
        }
        return count
    }

    /// Probe 전용: 앞 버퍼를 같은 상태로 처음부터 다시 그린 결과와 픽셀 단위로 비교한다.
    /// 부분 갱신이 잔상을 남기면 여기서 잡힌다.
    private func verifyFront() -> (mismatched: Int, total: Int) {
        guard let fresh = cells.referenceImage(of: drawn[front], scale: scale) else { return (0, 0) }
        return fresh.mismatches(against: buffers[front])
    }
}

/// 픽셀 좌표 사각형 — 위쪽 행이 0 (IOSurface 메모리 순서).
struct PixelRect {
    var x0: Int, x1: Int, y0: Int, y1: Int
    /// 그리드 행 — clear가 같은 행끼리 묶어 픽셀 행 우선으로 훑는다.
    var row: Int
}

/// CPU로 그리고 레이어 contents로 바로 건네는 IOSurface 한 장 (BGRA8, sRGB).
final class SurfaceBuffer {
    let surface: IOSurface
    private let context: CGContext

    init?(size: CGSize, scale: CGFloat) {
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let surface = IOSurface(properties: [
                  .width: width, .height: height,
                  .bytesPerElement: 4, .pixelFormat: 0x4247_5241, // 'BGRA'
              ]) else { return nil }
        // 색 공간을 태그하지 않으면 WindowServer가 sRGB 보정 없이 내보내 여백(레이어
        // 배경색)과 1단계 어긋난다.
        if let sRGB = CGColorSpace(name: CGColorSpace.sRGB)?.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, sRGB)
        }
        surface.lock(options: [], seed: nil)
        defer { surface.unlock(options: [], seed: nil) }
        guard let context = CGContext(
            data: surface.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: surface.bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setShouldSmoothFonts(false)
        context.setFillColor(Palette.background)
        context.fill(CGRect(origin: .zero, size: size))
        self.surface = surface
        self.context = context
        self.scale = scale
        pixelWidth = width
        pixelHeight = height
        // CG가 방금 칠한 픽셀을 그대로 쓴다 — 직접 반올림하면 1단계 어긋나 셀 모양 얼룩이 진다.
        surface.lock(options: .readOnly, seed: nil)
        backgroundPixel = surface.baseAddress.load(as: UInt32.self)
        surface.unlock(options: .readOnly, seed: nil)
    }

    private let scale: CGFloat
    let pixelHeight: Int
    let pixelWidth: Int
    /// 배경색 한 픽셀 (BGRA, little-endian 32비트로 쓰면 메모리에 B,G,R,A 순).
    private var backgroundPixel: UInt32

    /// 사각형들을 배경색으로 채운다. draw 블록 안에서만 부른다.
    ///
    /// 같은 그리드 행으로 이어지는 사각형 묶음을 픽셀 행 우선으로
    /// 훑는다. 셀마다 36행을 세로로 내려가면 행마다 다른 16KB 페이지라 TLB·프리페처가 놀고,
    /// 가로로 훑으면 같은 페이지 안에서 이어진다.
    func clear(_ rects: [PixelRect]) {
        let pixels = surface.baseAddress.assumingMemoryBound(to: UInt32.self)
        let rowPixels = surface.bytesPerRow / 4
        let fill = backgroundPixel
        var start = 0
        while start < rects.count {
            var end = start + 1
            while end < rects.count, rects[end].row == rects[start].row { end += 1 }
            let band = rects[start..<end]
            let top = max(0, band.map(\.y0).min()!)
            let bottom = min(pixelHeight, band.map(\.y1).max()!)
            if top < bottom {
                for y in top..<bottom {
                    let row = pixels + y * rowPixels
                    for rect in band where y >= rect.y0 && y < rect.y1 {
                        let x0 = max(0, rect.x0), x1 = min(pixelWidth, rect.x1)
                        var x = x0
                        while x < x1 { row[x] = fill; x += 1 }
                    }
                }
            }
            start = end
        }
    }

    /// Probe 전용: 다른 버퍼와 픽셀이 다른 개수.
    func mismatches(against other: SurfaceBuffer) -> (mismatched: Int, total: Int) {
        surface.lock(options: .readOnly, seed: nil)
        other.surface.lock(options: .readOnly, seed: nil)
        defer {
            other.surface.unlock(options: .readOnly, seed: nil)
            surface.unlock(options: .readOnly, seed: nil)
        }
        let a = surface.baseAddress.assumingMemoryBound(to: UInt32.self)
        let b = other.surface.baseAddress.assumingMemoryBound(to: UInt32.self)
        let rowA = surface.bytesPerRow / 4, rowB = other.surface.bytesPerRow / 4
        var bad = 0
        var ghost = 0          // other(앞 버퍼)에만 잉크 — 지워지지 않은 잔상
        var edgeX = [Int: Int](), edgeY = [Int: Int]()
        let cw = Probe.cellPixelWidth, ch = Probe.cellPixelHeight
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth where a[y * rowA + x] != b[y * rowB + x] {
                bad += 1
                if a[y * rowA + x] == backgroundPixel { ghost += 1 }
                if cw > 0 { edgeX[Int(Double(x).truncatingRemainder(dividingBy: cw)), default: 0] += 1 }
                if ch > 0 { edgeY[y % ch, default: 0] += 1 }
            }
        }
        if Probe.enabled, bad > 0 {
            Probe.log("  잔상(앞 버퍼에만 잉크) \(ghost)px · 셀 안 x위치 \(edgeX.sorted { $0.value > $1.value }.prefix(6)) · y위치 \(edgeY.sorted { $0.value > $1.value }.prefix(6))")
        }
        return (bad, pixelWidth * pixelHeight)
    }

    /// Probe 전용: GPU 결과(BGRA 바이트)와 비교 — 불일치 픽셀, 최대 채널 차이, 2 이상 차이 픽셀.
    func compare(bgra pixels: [UInt32], width: Int, height: Int) -> (mismatched: Int, maxDiff: Int, bigDiffs: Int) {
        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }
        let a = surface.baseAddress.assumingMemoryBound(to: UInt32.self)
        let rowA = surface.bytesPerRow / 4
        var bad = 0, maxDiff = 0, big = 0
        for y in 0..<min(height, pixelHeight) {
            for x in 0..<min(width, pixelWidth) {
                let p = a[y * rowA + x], q = pixels[y * width + x]
                guard p != q else { continue }
                bad += 1
                var d = 0
                for shift in [0, 8, 16] {
                    d = max(d, abs(Int((p >> UInt32(shift)) & 0xFF) - Int((q >> UInt32(shift)) & 0xFF)))
                }
                maxDiff = max(maxDiff, d)
                if d >= 2 {
                    big += 1
                    if Probe.cellPixelHeight > 0 {
                        Probe.bigCells.insert(Probe.CellKey(row: y / Probe.cellPixelHeight,
                                                            col: Int(Double(x) / Probe.cellPixelWidth)))
                    }
                }
            }
        }
        return (bad, maxDiff, big)
    }

    func draw(_ body: (CGContext) -> Void) {
        let tl = Probe.now()
        surface.lock(options: [], seed: nil)
        Probe.add("  lock", since: tl)
        body(context)
        let tf = Probe.now()
        context.flush()
        surface.unlock(options: [], seed: nil)
        Probe.add("  flush+unlock", since: tf)
    }
}

/// 모노스페이스 셀 크기.
struct CellMetrics {
    let font: CTFont
    let width: CGFloat
    let height: CGFloat
    let descent: CGFloat

    /// - Parameter scale: 화면 배율. 셀 폭을 정수 픽셀로 올린다 — 9.27pt × 2 = 18.54px처럼
    ///   경계 픽셀 열을 두 셀이 나눠 쓰면, 한쪽을 지울 때 옆 글자의 안티앨리어싱 한 열이
    ///   같이 지워진다(픽셀 검증으로 확인). 글자도 픽셀 격자에 맞아 더 선명하다.
    init(pointSize: CGFloat, scale: CGFloat) {
        let nsFont = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        font = nsFont as CTFont
        var glyph = CGGlyph(0)
        var unichar = UniChar(("M" as UnicodeScalar).value)
        CTFontGetGlyphsForCharacters(font, &unichar, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        width = (advance.width * scale).rounded(.up) / scale
        descent = CTFontGetDescent(font)
        height = (CTFontGetAscent(font) + descent + CTFontGetLeading(font)).rounded(.up)
    }
}

/// 문자 → (폰트, 글리프). SF Mono에 없는 한글·이모지·기호는 시스템 폴백 폰트를 찾는다.
/// 어항 그리드는 거의 ASCII라 ASCII는 배열로 바로 찾는다.
final class GlyphCache {
    struct Entry {
        let font: CTFont
        let glyph: CGGlyph
        let advance: CGFloat
        /// 글리프 원점 기준 잉크 영역(포인트). 지울 때 이 영역만 지운다.
        let ink: CGRect
    }

    private let base: CTFont
    private var ascii: [Entry?] = Array(repeating: nil, count: 128)
    private var cache: [UInt32: Entry] = [:]

    init(font: CTFont) { base = font }

    /// code는 셀 코드(TankView.code(of:)), ch는 처음 볼 때만 쓰는 원래 글자.
    subscript(code: UInt32, ch: @autoclosure () -> Character) -> Entry {
        if code < 128 {
            if let hit = ascii[Int(code)] { return hit }
            let entry = lookup(ch())
            ascii[Int(code)] = entry
            return entry
        }
        if let hit = cache[code] { return hit }
        let entry = lookup(ch())
        cache[code] = entry
        return entry
    }

    private func lookup(_ ch: Character) -> Entry {
        let string = String(ch) as CFString
        let utf16 = Array(String(ch).utf16)
        var font = CTFontCreateForString(base, string, CFRange(location: 0, length: utf16.count))
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        if !CTFontGetGlyphsForCharacters(font, utf16, &glyphs, utf16.count) {
            font = base // 찾지 못하면 기본 폰트의 .notdef라도 그린다
        }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advance, 1)
        var ink = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyphs, &ink, 1)
        return Entry(font: font, glyph: glyphs[0], advance: advance.width, ink: ink)
    }
}

/// (행, 폰트, 색)별로 글리프를 모아 CTFontDrawGlyphs 한 번에 그린다.
///
/// 행 띠로 잘라서 그린다 — SF Mono의 '|'는 셀 아래로 0.37pt 넘쳐, 아래 칸이 빈칸이면
/// 영영 안 지워지는 잔상이 쌓였다(픽셀 검증으로 확인). 자기 행 밖으로 잉크를 못 남기게 한다.
struct GlyphBatch {
    private struct Key: Hashable {
        let row: Int
        let font: ObjectIdentifier
        let color: UInt8
    }

    private var fonts: [ObjectIdentifier: CTFont] = [:]
    private var glyphs: [Key: [CGGlyph]] = [:]
    private var positions: [Key: [CGPoint]] = [:]
    private var bands: [Int: CGRect] = [:]

    /// - Parameter band: 이 글리프가 속한 행 띠(포인트 좌표). 그 밖은 잘린다.
    mutating func add(_ entry: GlyphCache.Entry, color: UInt8, at point: CGPoint, row: Int, band: CGRect) {
        let id = ObjectIdentifier(entry.font)
        fonts[id] = entry.font
        bands[row] = band
        let key = Key(row: row, font: id, color: color)
        glyphs[key, default: []].append(entry.glyph)
        positions[key, default: []].append(point)
    }

    func draw(in context: CGContext) {
        for (key, glyphs) in glyphs {
            guard let font = fonts[key.font], let points = positions[key], let band = bands[key.row] else { continue }
            context.saveGState()
            context.clip(to: band)
            context.setFillColor(Palette.colors[Int(key.color)])
            CTFontDrawGlyphs(font, glyphs, points, glyphs.count, context)
            context.restoreGState()
        }
    }
}
