import AppKit
import Foundation

/// `aquarium --card`: 저장된 어항을 SNS 공유용 PNG 명함으로 렌더링한다.
enum Card {
    static func generate() {
        guard let save = SaveStore.load(), !save.fish.isEmpty else {
            print(L10n.statusNoTank)
            return
        }

        // 카드용 미니 어항: 실제 저장 데이터를 복원하되 저장 파일은 건드리지 않는다
        let world = World(cols: 64, rows: 20, terminalDark: false,
                          restoring: save, ephemeral: true)
        world.setLighting(.day)
        for _ in 0..<50 { world.update() } // 물고기·공기방울이 자연스럽게 퍼지도록
        let grid = world.composeGrid()

        printPreview(grid)

        let nowEpoch = Date().timeIntervalSince1970
        let days = max(1, Int((nowEpoch - save.tankBornAt) / 86400) + 1)
        let names = save.fish.compactMap(\.name).prefix(3).joined(separator: ", ")
        var statLines = [
            L10n.cardSwimming(count: save.fish.count, days: days),
            save.fish.count > 3 ? L10n.cardFriends(names) : names,
            L10n.cardRecords(focus: save.focusDone ?? 0,
                             whale: save.visitorSeen?["whale"] ?? 0,
                             turtle: save.visitorSeen?["turtle"] ?? 0,
                             octopus: save.visitorSeen?["octopus"] ?? 0),
        ]
        if let commits = save.commitRewards, commits > 0 {
            statLines.append(L10n.cardCommits(commits))
        }
        statLines.append("github.com/agiletalk/Aquarium")

        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("aquarium-card.png")
        if writePNG(grid: grid, statLines: statLines, to: url) {
            print(L10n.cardSaved(url.path))
        } else {
            print(L10n.cardFailed)
        }
    }

    /// 터미널 컬러 미리보기
    private static func printPreview(_ grid: [[Cell]]) {
        var out = ""
        for row in grid {
            var lastColor: UInt8 = 0
            for cell in row {
                if cell.ch == " " {
                    out.append(" ")
                    continue
                }
                if cell.color != lastColor {
                    out += ANSI.fg(cell.color)
                    lastColor = cell.color
                }
                out.append(cell.ch)
            }
            out += ANSI.reset + "\n"
        }
        print(out, terminator: "")
    }

    // MARK: - PNG rendering (AppKit, headless)

    private static func writePNG(grid: [[Cell]], statLines: [String], to url: URL) -> Bool {
        let scale: CGFloat = 2 // retina
        let font = NSFont(name: "Menlo", size: 15) ?? .monospacedSystemFont(ofSize: 15, weight: .regular)
        let cellW = ("W" as NSString).size(withAttributes: [.font: font]).width
        let cellH: CGFloat = 19

        let pad: CGFloat = 28
        let titleH: CGFloat = 44
        let statLineH: CGFloat = 24
        let footerH = CGFloat(statLines.count) * statLineH + 20

        let cols = grid.first?.count ?? 0
        let width = pad * 2 + cellW * CGFloat(cols)
        let height = pad * 2 + titleH + cellH * CGFloat(grid.count) + footerH

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(width * scale),
                                         pixelsHigh: Int(height * scale),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return false }
        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return false }
        NSGraphicsContext.current = context

        // 배경 (터미널 느낌의 딥 네이비)
        NSColor(calibratedRed: 0.078, green: 0.086, blue: 0.13, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        // 제목
        let titleFont = NSFont.boldSystemFont(ofSize: 22)
        (L10n.cardTitle as NSString).draw(
            at: NSPoint(x: pad, y: height - pad - 30),
            withAttributes: [.font: titleFont,
                             .foregroundColor: NSColor(calibratedWhite: 0.95, alpha: 1)])

        // 어항 그리드 (AppKit은 좌하단 원점 → 위에서부터 그린다)
        let gridTop = height - pad - titleH
        for (r, row) in grid.enumerated() {
            for (c, cell) in row.enumerated() where cell.ch != " " {
                let point = NSPoint(x: pad + CGFloat(c) * cellW,
                                    y: gridTop - CGFloat(r + 1) * cellH)
                (String(cell.ch) as NSString).draw(
                    at: point,
                    withAttributes: [.font: font, .foregroundColor: rgb(cell.color)])
            }
        }

        // 하단 스탯
        let statFont = NSFont.systemFont(ofSize: 15)
        let statColors: [NSColor] = [
            NSColor(calibratedRed: 0.4, green: 0.85, blue: 1, alpha: 1),
            NSColor(calibratedWhite: 0.8, alpha: 1),
            NSColor(calibratedWhite: 0.65, alpha: 1),
            NSColor(calibratedWhite: 0.45, alpha: 1),
        ]
        for (i, line) in statLines.enumerated() {
            (line as NSString).draw(
                at: NSPoint(x: pad, y: footerH - 10 - CGFloat(i + 1) * statLineH + statLineH - 18 + 10),
                withAttributes: [.font: statFont,
                                 .foregroundColor: statColors[min(i, statColors.count - 1)]])
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    /// xterm-256 인덱스 → RGB
    private static func rgb(_ color: UInt8) -> NSColor {
        switch color {
        case 16...231:
            let index = Int(color) - 16
            let steps: [CGFloat] = [0, 95, 135, 175, 215, 255].map { $0 / 255 }
            return NSColor(calibratedRed: steps[index / 36],
                           green: steps[(index % 36) / 6],
                           blue: steps[index % 6], alpha: 1)
        case 232...255:
            let v = CGFloat(8 + 10 * (Int(color) - 232)) / 255
            return NSColor(calibratedWhite: v, alpha: 1)
        default:
            return NSColor(calibratedWhite: 0.9, alpha: 1)
        }
    }
}
