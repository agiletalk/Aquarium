import Foundation

/// 렌더러 중립 출력 모델. 색은 터미널 256색 인덱스 — 렌더러가 자기 팔레트로 옮긴다.

public struct Cell {
    public var ch: Character = " "
    public var color: UInt8 = 252
    public var glow: Bool = false // glowing cells skip night-time dimming

    public init(ch: Character = " ", color: UInt8 = 252, glow: Bool = false) {
        self.ch = ch
        self.color = color
        self.glow = glow
    }
}

public struct StatusSegment: Equatable {
    public var text: String
    public var color: UInt8

    public init(_ text: String, _ color: UInt8) {
        self.text = text
        self.color = color
    }
}

public struct PanelLine {
    public var text: String
    public var color: UInt8

    public init(_ text: String, _ color: UInt8) {
        self.text = text
        self.color = color
    }
}

/// 수조 위에 겹쳐 그리는 패널. 좌표는 1-based 터미널 행·열.
public struct Panel {
    public var startRow: Int
    public var startCol: Int
    public var innerWidth: Int
    public var title: String
    public var titleColor: UInt8
    public var lines: [PanelLine]

    public init(startRow: Int, startCol: Int, innerWidth: Int,
                title: String, titleColor: UInt8, lines: [PanelLine]) {
        self.startRow = startRow
        self.startCol = startCol
        self.innerWidth = innerWidth
        self.title = title
        self.titleColor = titleColor
        self.lines = lines
    }
}

public enum PanelContent {
    case box(Panel)
    /// 화면이 좁아 패널을 못 그릴 때 대신 띄울 안내 한 줄.
    case tooSmall(String)
}

/// 수조의 세로 배치 (0-indexed 그리드 행).
public struct TankLayout {
    public var swimMinRow: Int
    public var swimMaxRow: Int
    public var sandRow: Int
}

public enum TextWidth {
    /// Hangul renders 2 columns wide in the terminal.
    public static func displayWidth(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { width, scalar in
            let wide = (0xAC00...0xD7A3).contains(scalar.value)
                || (0x1100...0x115F).contains(scalar.value)
                || (0x3130...0x318F).contains(scalar.value)
            return width + (wide ? 2 : 1)
        }
    }

    public static func pad(_ s: String, to width: Int) -> String {
        s + String(repeating: " ", count: max(0, width - displayWidth(s)))
    }
}
