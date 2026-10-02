import AppKit
import AquariumCore
import CoreText
import IOSurface

/// 한 화면의 어항을 Core Text 글리프로 그린다 (render 층).
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
///   칠하고, CA에는 레이어 하나만 넘어간다. 뒤 버퍼는 두 프레임 전 상태라 직전
///   프레임에 바뀐 셀까지 함께 칠한다.
final class TankView: NSView {
    let metrics: CellMetrics
    let cols: Int
    let rows: Int
    weak var world: World?

    private let glyphs: GlyphCache
    /// 화면에 그려져 있는 셀 (상태줄 포함, rows × cols).
    private var shown: [DrawnCell]
    private var pending: [DrawnCell]
    /// 직전 프레임에 바뀐 셀 — 뒤 버퍼가 아직 모르는 변화.
    private var lastChanged: [Int] = []
    private var buffers: [SurfaceBuffer] = []
    private var front = 0
    private var scale: CGFloat = 0

    /// 셀 하나의 그린 결과. 공백은 glyph를 그리지 않는다.
    private struct DrawnCell: Equatable {
        var ch: Character = " "
        var color: UInt8 = 0
        /// 2칸 폭 글자(상태줄의 한글·이모지) — 2칸 가운데에 그린다.
        var wide = false
    }

    init(visibleRect: CGRect, metrics: CellMetrics) {
        self.metrics = metrics
        cols = max(1, Int(visibleRect.width / metrics.width))
        rows = max(1, Int(visibleRect.height / metrics.height))
        let size = CGSize(width: CGFloat(cols) * metrics.width, height: CGFloat(rows) * metrics.height)
        let frame = CGRect(x: (visibleRect.midX - size.width / 2).rounded(),
                           y: (visibleRect.midY - size.height / 2).rounded(),
                           width: size.width, height: size.height)
        glyphs = GlyphCache(font: metrics.font)
        shown = Array(repeating: DrawnCell(), count: cols * rows)
        pending = shown
        super.init(frame: frame)

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
        layer?.contentsScale = scale
        buffers = (0..<2).compactMap { _ in SurfaceBuffer(size: bounds.size, scale: scale) }
        // 새 버퍼는 비어 있다 — 두 장 모두 현재 셀 전체를 칠한다.
        for buffer in buffers { paint(Array(0..<(cols * rows)), into: buffer) }
        present()
    }

    /// 이번 tick의 상태를 셀로 펼치고, 바뀐 셀만 뒤 버퍼에 칠해 앞으로 돌린다.
    func refresh() {
        guard let world else { return }
        let grid = world.composeGrid()
        for r in 0..<min(rows - 1, grid.count) {
            let row = grid[r]
            let base = r * cols
            for c in 0..<min(cols, row.count) {
                let cell = row[c]
                // 셀 색은 반드시 displayColor로 — 밤 감광이 여기서 들어간다.
                pending[base + c] = cell.ch == " "
                    ? DrawnCell()
                    : DrawnCell(ch: cell.ch, color: world.displayColor(cell))
            }
        }
        layoutStatusLine(world.statusSegments(hints: false))

        var changed: [Int] = []
        for i in 0..<pending.count where pending[i] != shown[i] { changed.append(i) }
        // 상태줄은 2칸 글자가 섞여 셀 단위 비교로는 어긋날 수 있다 — 바뀌면 줄 전체.
        let statusBase = (rows - 1) * cols
        if changed.last.map({ $0 >= statusBase }) == true {
            changed.removeAll { $0 >= statusBase }
            changed += Array(statusBase..<(rows * cols))
        }
        swap(&shown, &pending)
        guard !changed.isEmpty || !lastChanged.isEmpty, buffers.count == 2 else { return }

        let back = buffers[1 - front]
        paint(Array(Set(changed).union(lastChanged)), into: back)
        lastChanged = changed
        front = 1 - front
        present()
    }

    private func present() {
        guard buffers.count == 2 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = buffers[front].surface
        CATransaction.commit()
    }

    /// 셀들의 배경을 칠하고 글리프를 그린다.
    private func paint(_ indices: [Int], into buffer: SurfaceBuffer) {
        guard !indices.isEmpty else { return }
        var batch = GlyphBatch()
        var rects: [CGRect] = []
        rects.reserveCapacity(indices.count)
        let cellSize = CGSize(width: metrics.width, height: metrics.height)
        for i in indices {
            let r = i / cols, c = i % cols
            let origin = CGPoint(x: CGFloat(c) * metrics.width,
                                 y: bounds.height - CGFloat(r + 1) * metrics.height)
            rects.append(CGRect(origin: origin, size: cellSize))
            let cell = shown[i]
            guard cell.ch != " " else { continue }
            let glyph = glyphs[cell.ch]
            // 대체 폰트의 한글은 2칸보다 좁다 — 왼쪽에 붙이면 "물 고 기"처럼 벌어진다.
            let inset = cell.wide ? max(0, (metrics.width * 2 - glyph.advance) / 2) : 0
            batch.add(glyph, color: cell.color,
                      at: CGPoint(x: origin.x + inset, y: origin.y + metrics.descent))
        }
        buffer.draw { context in
            // 배경은 CG를 거치지 않고 픽셀에 직접 쓴다. 셀마다 fill을 부르면 호출당 고정
            // 비용이 렌더 시간의 절반이었고, fill([CGRect])는 영역 합집합 계산으로 더 느렸다.
            buffer.clear(rects)
            batch.draw(in: context)
        }
    }

    /// 상태줄 — 터미널처럼 그리드 마지막 행. 한글·이모지는 2칸을 차지한다.
    private func layoutStatusLine(_ segments: [StatusSegment]) {
        let base = (rows - 1) * cols
        for c in 0..<cols { pending[base + c] = DrawnCell() }
        var col = 0
        for segment in segments {
            for ch in segment.text {
                guard col < cols else { return }
                let wide = Self.isWide(ch)
                if ch != " " { pending[base + col] = DrawnCell(ch: ch, color: segment.color, wide: wide) }
                col += wide ? 2 : 1
            }
        }
    }

    /// 터미널에서 2칸을 차지하는 문자 — Core의 TextWidth(한글)에 이모지를 더한다.
    /// 상태줄은 터미널에서 자동 줄바꿈 없이 잘리므로 폭 계산이 어긋나도 뒤만 밀린다.
    private static func isWide(_ ch: Character) -> Bool {
        if TextWidth.displayWidth(String(ch)) > 1 { return true }
        guard let scalar = ch.unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation
    }
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
    private let pixelHeight: Int
    private let pixelWidth: Int
    /// 배경색 한 픽셀 (BGRA, little-endian 32비트로 쓰면 메모리에 B,G,R,A 순).
    private var backgroundPixel: UInt32

    /// 포인트 좌표(좌하단 원점) 사각형들을 배경색으로 채운다. draw 블록 안에서만 부른다.
    func clear(_ rects: [CGRect]) {
        let pixels = surface.baseAddress.assumingMemoryBound(to: UInt32.self)
        let rowPixels = surface.bytesPerRow / 4
        let fill = backgroundPixel
        for rect in rects {
            let x0 = max(0, Int((rect.minX * scale).rounded(.down)))
            let x1 = min(pixelWidth, Int((rect.maxX * scale).rounded(.up)))
            // 메모리는 위쪽 행부터 — 좌하단 원점 y를 뒤집는다.
            let y0 = max(0, pixelHeight - Int((rect.maxY * scale).rounded(.up)))
            let y1 = min(pixelHeight, pixelHeight - Int((rect.minY * scale).rounded(.down)))
            guard x0 < x1, y0 < y1 else { continue }
            var row = pixels + y0 * rowPixels + x0
            for _ in y0..<y1 {
                // 셀 폭은 20픽셀 안팎이라 함수 호출(memset_pattern4)보다 직접 쓰는 편이 빠르다.
                for x in 0..<(x1 - x0) { row[x] = fill }
                row += rowPixels
            }
        }
    }

    func draw(_ body: (CGContext) -> Void) {
        surface.lock(options: [], seed: nil)
        body(context)
        context.flush()
        surface.unlock(options: [], seed: nil)
    }
}

/// 모노스페이스 셀 크기.
struct CellMetrics {
    let font: CTFont
    let width: CGFloat
    let height: CGFloat
    let descent: CGFloat

    init(pointSize: CGFloat) {
        let nsFont = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        font = nsFont as CTFont
        var glyph = CGGlyph(0)
        var unichar = UniChar(("M" as UnicodeScalar).value)
        CTFontGetGlyphsForCharacters(font, &unichar, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        width = advance.width
        descent = CTFontGetDescent(font)
        height = (CTFontGetAscent(font) + descent + CTFontGetLeading(font)).rounded(.up)
    }
}

/// 문자 → (폰트, 글리프). SF Mono에 없는 한글·이모지·기호는 시스템 폴백 폰트를 찾는다.
/// 어항 그리드는 거의 ASCII라 ASCII는 배열로 바로 찾는다(Character 해시를 피한다).
final class GlyphCache {
    struct Entry {
        let font: CTFont
        let glyph: CGGlyph
        let advance: CGFloat
    }

    private let base: CTFont
    private var ascii: [Entry?] = Array(repeating: nil, count: 128)
    private var cache: [Character: Entry] = [:]

    init(font: CTFont) { base = font }

    subscript(ch: Character) -> Entry {
        if let a = ch.asciiValue {
            if let hit = ascii[Int(a)] { return hit }
            let entry = lookup(ch)
            ascii[Int(a)] = entry
            return entry
        }
        if let hit = cache[ch] { return hit }
        let entry = lookup(ch)
        cache[ch] = entry
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
        return Entry(font: font, glyph: glyphs[0], advance: advance.width)
    }
}

/// (폰트, 색)별로 글리프를 모아 CTFontDrawGlyphs 한 번에 그린다.
struct GlyphBatch {
    private struct Key: Hashable {
        let font: ObjectIdentifier
        let color: UInt8
    }

    private var fonts: [ObjectIdentifier: CTFont] = [:]
    private var glyphs: [Key: [CGGlyph]] = [:]
    private var positions: [Key: [CGPoint]] = [:]

    mutating func add(_ entry: GlyphCache.Entry, color: UInt8, at point: CGPoint) {
        let id = ObjectIdentifier(entry.font)
        fonts[id] = entry.font
        let key = Key(font: id, color: color)
        glyphs[key, default: []].append(entry.glyph)
        positions[key, default: []].append(point)
    }

    func draw(in context: CGContext) {
        for (key, glyphs) in glyphs {
            guard let font = fonts[key.font], let points = positions[key] else { continue }
            context.setFillColor(Palette.colors[Int(key.color)])
            CTFontDrawGlyphs(font, glyphs, points, glyphs.count, context)
        }
    }
}
