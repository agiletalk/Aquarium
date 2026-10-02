import AppKit
import AquariumCore

/// 셀 하나의 그린 결과. code는 유니코드 스칼라 값(공백 = 32) 또는 번호표(최상위 비트).
struct DrawnCell: Equatable {
    var code: UInt32 = 32
    var color: UInt8 = 0
    /// 2칸 폭 글자(상태줄의 한글·이모지) — 2칸 가운데에 그린다.
    var wide = false
    var isBlank: Bool { code == 32 }
}

/// 렌더러가 공유하는 한 프레임의 셀 상태 — Core 그리드를 셀 코드로 펼치고 상태줄을 배치한다.
/// CPU(IOSurface)·GPU(Metal) 렌더러가 같은 결과를 그리도록 이 단계를 하나로 둔다.
final class CellFrame {
    let metrics: CellMetrics
    let cols: Int
    let rows: Int
    let glyphs: GlyphCache
    /// 이번 tick에 화면에 있어야 할 셀 (상태줄 포함, rows × cols, 위쪽 행부터).
    private(set) var cells: [DrawnCell]

    /// 스칼라 하나로 안 떨어지는 글자(이모지 조합 등)의 번호표.
    private var interned: [Character: UInt32] = [:]
    private var internedChars: [Character] = []

    init(cols: Int, rows: Int, metrics: CellMetrics) {
        self.metrics = metrics
        self.cols = cols
        self.rows = rows
        glyphs = GlyphCache(font: metrics.font)
        cells = Array(repeating: DrawnCell(), count: cols * rows)
    }

    /// 그리드가 차지하는 포인트 크기.
    var size: CGSize { CGSize(width: CGFloat(cols) * metrics.width, height: CGFloat(rows) * metrics.height) }

    func update(from world: World) {
        let grid = world.composeGrid()
        // 셀 색은 반드시 displayColor로 — 밤 감광이 여기서 들어간다. 셀마다 Core를 부르지
        // 않고 이번 프레임의 256색 표를 displayColor로 한 번 만든다(glow 셀은 감광 없음).
        let dimmedTable = (0...255).map { world.displayColor(Cell(color: UInt8($0))) }
        for r in 0..<min(rows - 1, grid.count) {
            let row = grid[r]
            let base = r * cols
            for c in 0..<min(cols, row.count) {
                let cell = row[c]
                cells[base + c] = cell.ch == " "
                    ? DrawnCell()
                    : DrawnCell(code: code(of: cell.ch),
                                color: cell.glow ? cell.color : dimmedTable[Int(cell.color)])
            }
        }
        layoutStatusLine(world.statusSegments(hints: false))
    }

    func glyph(for cell: DrawnCell) -> GlyphCache.Entry {
        glyphs[cell.code, character(of: cell.code)]
    }

    /// 글리프 원점 — 셀 왼쪽 아래 기준 (포인트, 좌하단 원점). 2칸 글자는 2칸 가운데.
    func glyphOffset(for cell: DrawnCell, _ glyph: GlyphCache.Entry) -> CGPoint {
        // 대체 폰트의 한글은 2칸보다 좁다 — 왼쪽에 붙이면 "물 고 기"처럼 벌어진다.
        let inset = cell.wide ? max(0, (metrics.width * 2 - glyph.advance) / 2) : 0
        return CGPoint(x: inset, y: metrics.descent)
    }

    /// 행 r의 띠 (포인트, 좌하단 원점). 글리프는 이 띠로 잘려 그려진다.
    func rowBand(_ r: Int) -> CGRect {
        CGRect(x: 0, y: size.height - CGFloat(r + 1) * metrics.height,
               width: size.width, height: metrics.height)
    }

    /// CPU 경로의 글리프 한 개를 배치에 넣는다 (그리드 좌표 → 포인트).
    func addGlyph(_ cell: DrawnCell, row r: Int, col c: Int, to batch: inout GlyphBatch) {
        guard !cell.isBlank else { return }
        let glyph = glyph(for: cell)
        let offset = glyphOffset(for: cell, glyph)
        batch.add(glyph, color: cell.color,
                  at: CGPoint(x: CGFloat(c) * metrics.width + offset.x,
                              y: size.height - CGFloat(r + 1) * metrics.height + offset.y),
                  row: r, band: rowBand(r))
    }

    /// 검증용 기준 그림 — 주어진 상태를 CPU 경로로 처음부터 그린다.
    func referenceImage(of state: [DrawnCell], scale: CGFloat) -> SurfaceBuffer? {
        guard let fresh = SurfaceBuffer(size: size, scale: scale) else { return nil }
        var batch = GlyphBatch()
        for r in 0..<rows {
            for c in 0..<cols { addGlyph(state[r * cols + c], row: r, col: c, to: &batch) }
        }
        fresh.draw { batch.draw(in: $0) }
        return fresh
    }

    /// 상태줄 — 터미널처럼 그리드 마지막 행. 한글·이모지는 2칸을 차지한다.
    private func layoutStatusLine(_ segments: [StatusSegment]) {
        let base = (rows - 1) * cols
        for c in 0..<cols { cells[base + c] = DrawnCell() }
        var col = 0
        for segment in segments {
            for ch in segment.text {
                guard col < cols else { return }
                let code = code(of: ch)
                // 터미널 폭 규칙(한글·이모지)에 더해, 대체 폰트가 실제로 넓게 그리는 글자
                // (✉ 같은 기호가 컬러 이모지로 그려지는 경우)도 2칸을 준다 — 안 그러면 뒤 글자와 겹친다.
                let wide = Self.isWide(ch) || glyphs[code, ch].advance > metrics.width * 1.3
                if ch != " " { cells[base + col] = DrawnCell(code: code, color: segment.color, wide: wide) }
                col += wide ? 2 : 1
            }
        }
    }

    /// 글자 → 셀 코드. 어항 그리드는 거의 ASCII라 asciiValue로 바로 끝난다.
    private func code(of ch: Character) -> UInt32 {
        if let a = ch.asciiValue { return UInt32(a) }
        let scalars = ch.unicodeScalars
        if scalars.count == 1, let s = scalars.first { return s.value }
        if let id = interned[ch] { return id }
        let id = 0x8000_0000 | UInt32(internedChars.count)
        interned[ch] = id
        internedChars.append(ch)
        return id
    }

    func character(of code: UInt32) -> Character {
        code & 0x8000_0000 != 0
            ? internedChars[Int(code & 0x7FFF_FFFF)]
            : Character(UnicodeScalar(code) ?? " ")
    }

    /// 터미널에서 2칸을 차지하는 문자 — Core의 TextWidth(한글)에 이모지를 더한다.
    /// 상태줄은 터미널에서 자동 줄바꿈 없이 잘리므로 폭 계산이 어긋나도 뒤만 밀린다.
    private static func isWide(_ ch: Character) -> Bool {
        if TextWidth.displayWidth(String(ch)) > 1 { return true }
        guard let scalar = ch.unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation
    }
}

/// 어항 렌더러 — CPU(TankView)와 GPU(MetalTankView). WallpaperController가 설정에 따라 고른다.
protocol TankRenderer: NSView {
    var cells: CellFrame { get }
    var world: World? { get set }
    /// 이번 tick의 상태를 반영해 그린다.
    func refresh()
}

extension TankRenderer {
    var cols: Int { cells.cols }
    var rows: Int { cells.rows }

    /// visibleRect 안에 그리드를 가운데 정렬한 뷰 프레임.
    static func gridFrame(in visibleRect: CGRect, metrics: CellMetrics) -> (cols: Int, rows: Int, frame: CGRect) {
        let cols = max(1, Int(visibleRect.width / metrics.width))
        let rows = max(1, Int(visibleRect.height / metrics.height))
        let size = CGSize(width: CGFloat(cols) * metrics.width, height: CGFloat(rows) * metrics.height)
        let frame = CGRect(x: (visibleRect.midX - size.width / 2).rounded(),
                           y: (visibleRect.midY - size.height / 2).rounded(),
                           width: size.width, height: size.height)
        return (cols, rows, frame)
    }
}
