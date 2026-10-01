import AquariumCore
import Foundation

/// 터미널 렌더러 — World의 셀 그리드·상태줄·패널을 ANSI 프레임 한 장으로 만든다.
extension World {
    /// 모듈 격자는 페이로드가 고정이라 한 번만 만든다 (매 프레임 CoreImage를 돌릴 순 없다).
    static let qrModules: [[Bool]]? = QRCode.modules(for: loungeQRPayload)

    /// 공개 레포에 사내 채널 주소를 박을 수 없으니 주소는 주입받는다.
    /// 라운지 맥에서 env 한 줄만 바꾸면 되고 재빌드가 필요 없다.
    ///
    /// 기본값에서 "https://"를 뺀 건 코드 크기 때문이다. 8자가 줄면서 QR 버전이
    /// 3→2로 내려가 화면에서 33x17 → 29x15가 된다. 폰 카메라는 스킴 없는 도메인도
    /// 링크로 인식한다. 주소가 길수록 QR이 커지므로 env로 바꿀 때도 짧을수록 좋다.
    static var loungeQRPayload: String {
        let env = ProcessInfo.processInfo.environment["AQUARIUM_LOUNGE_QR"] ?? ""
        return env.isEmpty ? "github.com/agiletalk/Aquarium" : env
    }

    func render() -> String {
        guard cols >= 34, rows >= 12 else {
            return ANSI.home + ANSI.clear + ANSI.fg(220)
                + L10n.enlargeTerminal + ANSI.reset
        }

        let grid = composeGrid()

        // 프레임 전체를 동기화 출력으로 감싼다 — 터미널이 중간 상태를 그리지 않는다.
        var out = ANSI.syncBegin + ANSI.home
        var lastColor: UInt8 = 0
        for (r, row) in grid.enumerated() {
            if r > 0 { out += "\r\n" }
            for cell in row {
                if cell.ch == " " {
                    out.append(" ")
                    continue
                }
                let color = displayColor(cell)
                if color != lastColor {
                    out += ANSI.fg(color)
                    lastColor = color
                }
                out.append(cell.ch)
            }
        }
        out += "\r\n" + statusLine() + "\u{1B}[K"
        if rosterOpen { out += overlay(rosterPanel()) }
        if mailboxOpen { out += overlay(mailboxPanel()) }
        if sponsorOpen { out += sponsorOverlay() }
        // 패널 셋 중 하나라도 열려 있으면 QR을 접는다 — 겹쳐 그리면 둘 다 못 읽는다.
        // (라운지 키오스크 가드가 패널 토글을 막지만 코드로도 보장한다.)
        if loungeQRShowing {
            out += loungeQROverlay()
        }
        return out + ANSI.syncEnd
    }

    private func statusLine() -> String {
        statusSegments().map { ANSI.fg($0.color) + $0.text }.joined() + ANSI.reset
    }

    private func pos(_ row: Int, _ col: Int) -> String {
        "\u{1B}[\(row);\(col)H"
    }

    /// Drawn with absolute cursor positioning over the live tank, so
    /// double-width Hangul can't shift the grid cells around it.
    private func overlay(_ content: PanelContent) -> String {
        switch content {
        case .tooSmall(let message):
            return pos(3, 3) + ANSI.fg(220) + " " + message + " " + ANSI.reset
        case .box(let panel):
            let innerW = panel.innerWidth
            let startCol = panel.startCol
            var out = pos(panel.startRow, startCol) + ANSI.fg(245) + "+-"
                + ANSI.fg(panel.titleColor) + panel.title
                + ANSI.fg(245) + String(repeating: "-", count: max(0, innerW - TextWidth.displayWidth(panel.title) - 1)) + "+"
            var r = panel.startRow + 1
            for line in panel.lines {
                guard r < rows - 1 else { break }
                out += pos(r, startCol) + ANSI.fg(245) + "|"
                    + ANSI.fg(line.color) + TextWidth.pad(line.text, to: innerW)
                    + ANSI.fg(245) + "|"
                r += 1
            }
            out += pos(r, startCol) + ANSI.fg(245) + "+" + String(repeating: "-", count: innerW) + "+"
            return out + ANSI.reset
        }
    }

    /// 후원 안내 패널 (s 키)
    private func sponsorOverlay() -> String {
        let gridRows = rows - 1
        guard cols >= 50, gridRows >= 10 else { return overlay(.tooSmall(L10n.sponsorEnlarge)) }
        let innerW = min(52, cols - 8)
        let lines: [PanelLine] = [
            PanelLine(" " + L10n.sponsorThanks1, 252),
            PanelLine(" " + L10n.sponsorThanks2, 252),
            PanelLine("", 252),
            PanelLine(" \u{2615}  " + Support.display, 45),
            PanelLine("", 252),
            PanelLine(" " + L10n.sponsorOpenHint, 245),
        ]
        return overlay(.box(Panel(startRow: 4,
                                  startCol: max(2, (cols - innerW - 2) / 2 + 1),
                                  innerWidth: innerW,
                                  title: L10n.sponsorTitle, titleColor: 219,
                                  lines: lines)))
    }

    /// 라운지 설치 QR. 다른 패널과 달리 +---+ 테두리를 두르지 않는다 —
    /// QR은 사방 4모듈의 *밝은* 여백이 있어야 스캐너가 경계를 찾는데,
    /// ASCII 테두리는 여백 노릇을 못 하고 오히려 코드를 침범한다.
    ///
    /// 그리드 셀이 아니라 오버레이로 그리는 이유: render()에서 오버레이는 그리드
    /// 뒤에 붙으므로 dimmed()를 통째로 우회한다. 그리드에 넣었다면 밤에 명암이
    /// 뭉개져 스캔이 안 되고, 셀마다 glow를 강제해야 했다.
    func loungeQROverlay() -> String {
        guard let modules = World.qrModules, let qrCols = modules.first?.count else { return "" }
        let qrRows = modules.count / 2 // 하프블록 한 줄 = 모듈 두 행

        // 우측 하단. 행 0은 제목·달(cols/8)·여름 태양(오른쪽 어깨)이 이미 쓰고 있다.
        // 아래에서부터 쌓지 않으면 모래와 바닥 테두리를 덮어 "자갈에 파묻힌 QR"이 된다.
        let layout = self.layout
        let bottom = layout.sandRow           // 1-based 터미널 행 = 그리드 sandRow-1 (모래 바로 위)
        let top = bottom - qrRows + 1
        let left = cols - qrCols - 2
        // 캡션 한 줄(top-1)까지 자리가 나와야 하고, 물고기가 헤엄칠 여유도 남겨둔다.
        // 코드가 작아지면서 좁은 창에도 들어가게 됐지만, 어항의 절반을 넘게 차지하면
        // 수조가 아니라 QR을 전시하는 꼴이라 그때는 통째로 접는다.
        let swimHeight = layout.swimMaxRow - layout.swimMinRow + 1
        guard qrCols + 6 <= cols, top >= layout.swimMinRow + 3, bottom < rows,
              qrRows * 2 <= swimHeight else { return "" }

        // 밝은 터미널이면 흰 카드를 깔지 않고 배경을 그대로 비춘다. 밝은 모듈이
        // 터미널 배경색이 되므로 여전히 균일하고, 화면에서 차지하는 무게가 확 준다.
        // 어두운 터미널·응답 없는 터미널은 흰 카드를 유지한다 — 검은 모듈을 어두운
        // 배경에 그리면 대비가 사라지고, 반전 QR은 못 읽는 스캐너가 있다.
        let seeThrough = terminalDark == false

        let caption = L10n.loungeQRCaption
        let capCol = max(1, left + (qrCols - TextWidth.displayWidth(caption)) / 2)
        var out = pos(top - 1, capCol) + ANSI.fg(seeThrough ? 240 : 231) + caption

        if seeThrough {
            // 배경을 안 칠하니 색 지정이 앞에 한 번이면 끝난다 (프레임 바이트도 준다).
            out += ANSI.bgDefault + ANSI.fg(16)
            for r in 0..<qrRows {
                out += pos(top + r, left)
                for c in 0..<qrCols {
                    let up = modules[r * 2][c], down = modules[r * 2 + 1][c]
                    // 밝은 모듈은 공백 — 배경을 칠하지 않되 뒤의 수조는 지워진다.
                    out.append(up && down ? "\u{2588}" : up ? "\u{2580}" : down ? "\u{2584}" : " ")
                }
            }
        } else {
            for r in 0..<qrRows {
                out += pos(top + r, left)
                var lastPair: (UInt8, UInt8)? = nil
                for c in 0..<qrCols {
                    // ▀ 는 전경색이 위쪽 절반, 배경색이 아래쪽 절반을 칠한다.
                    // 터미널 셀이 대략 세로:가로 2:1이라 이 매핑에서 모듈이 정사각형이 된다.
                    let pair: (UInt8, UInt8) = (modules[r * 2][c] ? 16 : 231,
                                                modules[r * 2 + 1][c] ? 16 : 231)
                    if pair != lastPair ?? (255, 255) {
                        out += ANSI.fg(pair.0) + ANSI.bg(pair.1)
                        lastPair = pair
                    }
                    out.append("\u{2580}")
                }
            }
        }
        // 배경색을 남긴 채 끝내면 다음 프레임 그리드에 색 줄무늬로 번진다
        // (render()는 전경색만 디핑하고 매 프레임 clear를 하지 않는다).
        return out + ANSI.reset
    }
}
