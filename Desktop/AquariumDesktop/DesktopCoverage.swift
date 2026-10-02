import AppKit

/// 일반 창들이 화면의 한 영역을 얼마나 덮고 있는지 (0...1).
///
/// 바탕화면 레벨 창은 AppKit의 occlusionState가 다른 앱 창에 가려져도 바뀌지
/// 않을 수 있어(스파이크로 확인), 창 목록으로 직접 계산한다. 거친 격자 표본이면 충분하다 —
/// 판정은 "거의 다 덮였나"뿐이다.
enum DesktopCoverage {
    /// - Parameter rect: 전역 좌표(AppKit, 좌하단 원점)의 관심 영역.
    static func fraction(of rect: CGRect, excludingPID pid: pid_t) -> Double {
        // [[String: Any]]로 브리징하면 창마다 딕셔너리를 통째로 복사한다 — 멈춘 동안
        // 0.2초마다 부르므로 NSArray/NSDictionary로 필요한 키만 읽는다.
        guard rect.width > 0, rect.height > 0,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as NSArray? else { return 0 }
        // CGWindowList는 좌상단 원점(주 화면 기준) — AppKit 좌표로 뒤집는다.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var windows: [CGRect] = []
        for case let info as NSDictionary in list {
            guard (info[kCGWindowLayer] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowOwnerPID] as? NSNumber)?.int32Value != pid,
                  (info[kCGWindowAlpha] as? NSNumber)?.doubleValue ?? 1 > 0.5,
                  let dict = info[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            windows.append(CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY,
                                  width: bounds.width, height: bounds.height))
        }
        guard !windows.isEmpty else { return 0 }

        let columns = 48, rows = 30
        var covered = 0
        for r in 0..<rows {
            for c in 0..<columns {
                let point = CGPoint(x: rect.minX + (CGFloat(c) + 0.5) * rect.width / CGFloat(columns),
                                    y: rect.minY + (CGFloat(r) + 0.5) * rect.height / CGFloat(rows))
                if windows.contains(where: { $0.contains(point) }) { covered += 1 }
            }
        }
        return Double(covered) / Double(columns * rows)
    }
}
