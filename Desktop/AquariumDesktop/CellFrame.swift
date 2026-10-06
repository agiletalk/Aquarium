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

    /// - Parameter panel: 수조 위에 겹쳐 그릴 패널(도감·편지함·업적·후원). nil이면 없음.
    func update(from world: World, panel: PanelContent? = nil) {
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
        if let panel { overlay(panel) }
        layoutStatusLine(world.statusSegments(hints: false))
    }

    /// 터미널 렌더러와 같은 +---+ 패널을 셀에 겹쳐 쓴다. Panel 좌표는 1-based 터미널 행·열.
    /// 2칸 글자(한글·이모지)는 실제 폭대로 놓고 오른쪽 테두리 열은 고정한다 — 터미널은
    /// 이모지를 1칸으로 패딩해 테두리가 밀리지만, 여기서는 글리프 폭을 알고 있다.
    private func overlay(_ content: PanelContent) {
        let lastGridRow = rows - 2   // 상태줄 위까지
        func put(_ text: String, row: Int, col: Int, color: UInt8, until end: Int) -> Int {
            guard row >= 0, row <= lastGridRow else { return col }
            var c = col
            for ch in text {
                let w = width(of: ch)
                guard c + w - 1 <= end, c < cols else { break }
                cells[row * cols + c] = ch == " "
                    ? DrawnCell()
                    : DrawnCell(code: code(of: ch), color: color, wide: w == 2)
                if w == 2, c + 1 < cols { cells[row * cols + c + 1] = DrawnCell() }
                c += w
            }
            return c
        }
        func blank(row: Int, from: Int, to: Int) {
            guard row >= 0, row <= lastGridRow, from <= to else { return }
            for c in max(0, from)...min(cols - 1, to) { cells[row * cols + c] = DrawnCell() }
        }

        switch content {
        case .tooSmall(let message):
            _ = put(" " + message + " ", row: 2, col: 2, color: 220, until: cols - 1)
        case .box(let panel):
            let left = panel.startCol - 1
            let right = left + panel.innerWidth + 1          // 오른쪽 테두리 열
            guard right < cols else { return }
            var r = panel.startRow - 1
            // 윗변: +- 제목 ----+
            var c = put("+-", row: r, col: left, color: 245, until: right)
            c = put(panel.title, row: r, col: c, color: panel.titleColor, until: right - 1)
            _ = put(String(repeating: "-", count: max(0, right - c)), row: r, col: c, color: 245, until: right - 1)
            _ = put("+", row: r, col: right, color: 245, until: right)
            r += 1
            for line in panel.lines {
                guard r < lastGridRow else { break }
                _ = put("|", row: r, col: left, color: 245, until: left)
                blank(row: r, from: left + 1, to: right - 1)
                _ = put(line.text, row: r, col: left + 1, color: line.color, until: right - 1)
                _ = put("|", row: r, col: right, color: 245, until: right)
                r += 1
            }
            _ = put("+" + String(repeating: "-", count: panel.innerWidth) + "+",
                    row: r, col: left, color: 245, until: right)
        }
    }

    /// 셀 폭 — 터미널 폭 규칙(한글·이모지)에 더해, 대체 폰트가 실제로 넓게 그리는 글자도 2칸.
    /// 잉크가 셀 오른쪽을 넘는 글자(예: 대체 폰트의 ✔)도 2칸으로 보낸다 — 1칸 글자는 셀 폭으로만
    /// 지워서 넘친 잉크가 이웃 칸에 남는다. 2칸 경로는 두 칸으로 잘라 그리고 두 칸을 지운다.
    private func width(of ch: Character) -> Int {
        if Self.isWide(ch) { return 2 }
        let glyph = glyphs[code(of: ch), ch]
        return glyph.advance > metrics.width * 1.3 || glyph.ink.maxX > metrics.width ? 2 : 1
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
        let point = CGPoint(x: CGFloat(c) * metrics.width + offset.x,
                            y: size.height - CGFloat(r + 1) * metrics.height + offset.y)
        if cell.wide {
            // 2칸 글자(한글·이모지)는 자기 두 칸으로 자른다 — 컬러 이모지는 2칸보다 넓게 그려져
            // 세 번째 칸에 잉크를 남겼다(픽셀 검증). GPU 렌더러의 2칸 슬롯과도 같아진다.
            var band = rowBand(r)
            band.origin.x = CGFloat(c) * metrics.width
            band.size.width = metrics.width * 2
            batch.add(glyph, color: cell.color, at: point, clip: -(r * cols + c + 1), band: band)
        } else {
            batch.add(glyph, color: cell.color, at: point, clip: r, band: rowBand(r))
        }
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
                let wide = width(of: ch) == 2
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
    /// 수조 위에 겹쳐 그릴 패널. 매 tick 컨트롤러가 정한다.
    var panel: PanelContent? { get set }
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
