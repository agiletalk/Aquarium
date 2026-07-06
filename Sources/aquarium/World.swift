import Foundation

struct Cell {
    var ch: Character = " "
    var color: UInt8 = 252
}

struct Species {
    let right: [Character]
    let left: [Character]
    let striped: Bool
    var speed: ClosedRange<Double> = 0.15...0.4
}

// index 0 is the baby fish; adults are 1 and up
let allSpecies: [Species] = [
    Species(right: Array("><>"), left: Array("<><"), striped: false),
    Species(right: Array("><(°>"), left: Array("<°)><"), striped: false),
    Species(right: Array("><((°>"), left: Array("<°))><"), striped: false),
    Species(right: Array("><(((°>"), left: Array("<°)))><"), striped: false),
    Species(right: Array("><|||°>"), left: Array("<°|||><"), striped: true),
    Species(right: Array("><^^^°>"), left: Array("<°^^^><"), striped: true),
    Species(right: Array("><}}}°>"), left: Array("<°{{{><"), striped: true),
    Species(right: Array(">-=(((°>"), left: Array("<°)))=-<"), striped: false, speed: 0.3...0.6),
    Species(right: Array("><(((°=>"), left: Array("<=°)))><"), striped: false, speed: 0.3...0.6),
    Species(right: Array("~~(((°>"), left: Array("<°)))~~"), striped: false, speed: 0.08...0.18),
    Species(right: Array(">->"), left: Array("<-<"), striped: false, speed: 0.35...0.65),
]

let fishPalette: [UInt8] = [196, 202, 208, 214, 220, 226, 201, 213, 199, 51, 45, 39, 118, 82, 141, 129]

struct Fish {
    var x: Double
    var y: Double
    var vy: Double = 0
    var dir: Double // -1 (left) or 1 (right)
    var speed: Double
    var species: Int
    var color: UInt8
    var color2: UInt8 = 231
    var growAt: Double? // nil means adult
    var eaten: Int = 0

    var art: [Character] { dir > 0 ? allSpecies[species].right : allSpecies[species].left }
    var mouthX: Double { dir > 0 ? x + Double(art.count - 1) : x }
}

struct Bubble {
    var x: Double
    var y: Double
    var phase: Double
    var speed: Double
}

struct Food {
    var x: Double
    var y: Double
    var vy: Double
    var restingSince: Double?
}

struct Weed {
    var x: Int
    var height: Int
    var phase: Double
}

struct Jellyfish {
    var x: Double
    var y: Double
    var vy: Double = 0
    var phase: Double
    var driftSeed: Double

    // Pulse cycle: contract (jet upward) then relax (drift down)
    func isContracted(at now: Double) -> Bool {
        let cycle = 2.6
        return (now + phase).truncatingRemainder(dividingBy: cycle) / cycle < 0.35
    }
}

final class World {
    private(set) var cols: Int
    private(set) var rows: Int

    var fish: [Fish] = []
    var bubbles: [Bubble] = []
    var food: [Food] = []
    var weeds: [Weed] = []
    var jellyfish: [Jellyfish] = []

    private var chestX: Int? // left column of the chest; nil when the tank is too narrow
    private var chestOpenUntil: Double = 0
    private var chestNextOpen: Double = 0

    private var message = ""
    private var messageUntil: Double = 0
    private let startTime: Double
    private var nextBreed: Double
    private var tick = 0

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    // Vertical layout (0-indexed grid rows; the last terminal row is the status line)
    private var gridRows: Int { rows - 1 }
    private var surfaceRow: Int { 1 }
    private var bottomBorderRow: Int { gridRows - 1 }
    private var sandRow: Int { gridRows - 2 }
    private var swimMinRow: Int { 2 }
    private var swimMaxRow: Int { sandRow - 1 }

    private var maxFish: Int { max(8, min(28, cols * rows / 80)) }

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        startTime = ProcessInfo.processInfo.systemUptime
        nextBreed = startTime + Double.random(in: 15...25)
        plantWeeds()
        placeChest()
        spawnJellyfish()
        for _ in 0..<5 { spawnAdult() }
    }

    func resize(cols: Int, rows: Int) {
        let colsChanged = cols != self.cols
        self.cols = cols
        self.rows = rows
        if colsChanged {
            plantWeeds()
            placeChest()
            spawnJellyfish()
        }
        for i in fish.indices { clampToTank(&fish[i]) }
        food.removeAll { $0.x >= Double(cols - 1) }
        bubbles.removeAll { $0.x >= Double(cols - 1) }
    }

    // MARK: - Spawning

    private func plantWeeds() {
        weeds = []
        guard cols > 12 else { return }
        var x = Int.random(in: 3...6)
        while x < cols - 3 {
            let maxHeight = max(2, min(6, rows / 4))
            weeds.append(Weed(x: x,
                              height: Int.random(in: 2...maxHeight),
                              phase: Double.random(in: 0...(2 * .pi))))
            x += Int.random(in: 5...11)
        }
    }

    private func placeChest() {
        guard cols >= 44, sandRow - 2 >= swimMinRow else {
            chestX = nil
            return
        }
        chestX = Int.random(in: 4...(cols - 12))
        chestNextOpen = now + Double.random(in: 5...12)
        chestOpenUntil = 0
    }

    private func spawnJellyfish() {
        jellyfish = []
        let count = cols >= 70 ? 2 : (cols >= 40 ? 1 : 0)
        for _ in 0..<count {
            jellyfish.append(Jellyfish(
                x: Double.random(in: 2...Double(max(3, cols - 8))),
                y: Double.random(in: Double(swimMinRow)...Double(max(swimMinRow, swimMaxRow - 1))),
                phase: Double.random(in: 0...(2 * .pi)),
                driftSeed: Double.random(in: 0...(2 * .pi))))
        }
    }

    private func spawnAdult() {
        let species = Int.random(in: 1..<allSpecies.count)
        var f = Fish(x: Double.random(in: 2...Double(max(3, cols - 10))),
                     y: Double.random(in: Double(swimMinRow)...Double(max(swimMinRow, swimMaxRow))),
                     dir: Bool.random() ? 1 : -1,
                     speed: Double.random(in: allSpecies[species].speed),
                     species: species,
                     color: fishPalette.randomElement()!)
        clampToTank(&f)
        fish.append(f)
    }

    private func spawnBaby(near parent: Fish) {
        var baby = Fish(x: parent.x,
                        y: parent.y,
                        dir: Bool.random() ? 1 : -1,
                        speed: Double.random(in: 0.2...0.45),
                        species: 0,
                        color: parent.color,
                        growAt: now + Double.random(in: 30...55))
        clampToTank(&baby)
        fish.append(baby)
    }

    private func clampToTank(_ f: inout Fish) {
        let maxX = Double(max(2, cols - 2 - f.art.count))
        f.x = min(max(1, f.x), maxX)
        f.y = min(max(Double(swimMinRow), f.y), Double(max(swimMinRow, swimMaxRow)))
    }

    // MARK: - Input

    func feed() {
        guard cols > 8, food.count < 60 else { return }
        for _ in 0..<Int.random(in: 4...7) {
            food.append(Food(x: Double.random(in: 2...Double(cols - 3)),
                             y: Double(surfaceRow + 1),
                             vy: Double.random(in: 0.12...0.28),
                             restingSince: nil))
        }
        post("먹이를 뿌렸어요! 물고기들이 몰려듭니다~")
    }

    private func post(_ text: String) {
        message = text
        messageUntil = now + 4
    }

    // MARK: - Simulation

    func update() {
        tick += 1
        let now = self.now

        updateFish(now)
        updateFood(now)
        updateBubbles(now)
        updateJellyfish(now)
        updateChest(now)

        // The tank slowly fills up on its own; feeding just speeds it along.
        if now >= nextBreed {
            nextBreed = now + Double.random(in: 22...38)
            if fish.count < maxFish, let parent = fish.randomElement() {
                spawnBaby(near: parent)
                post("아기 물고기가 태어났어요! (\(fish.count)마리)")
            }
        }
    }

    private func updateFish(_ now: Double) {
        for i in fish.indices {
            var f = fish[i]

            if let target = nearestFood(for: f) {
                let dx = target.x - f.mouthX
                if abs(dx) > 1 { f.dir = dx > 0 ? 1 : -1 }
                f.vy = max(-0.3, min(0.3, (target.y - f.y) * 0.12))
                f.x += f.dir * f.speed * 1.8
            } else {
                if Double.random(in: 0...1) < 0.01 { f.dir = -f.dir }
                if Double.random(in: 0...1) < 0.05 { f.vy = Double.random(in: -0.1...0.1) }
                f.x += f.dir * f.speed
            }

            f.y += f.vy
            f.vy *= 0.96

            let maxX = Double(max(2, cols - 2 - f.art.count))
            if f.x <= 1 { f.x = 1; f.dir = 1 }
            if f.x >= maxX { f.x = maxX; f.dir = -1 }
            if f.y <= Double(swimMinRow) { f.y = Double(swimMinRow); f.vy = abs(f.vy) }
            if f.y >= Double(swimMaxRow) { f.y = Double(swimMaxRow); f.vy = -abs(f.vy) }

            for fi in food.indices.reversed() {
                if abs(food[fi].x - f.mouthX) < 2.0, abs(food[fi].y - f.y) < 1.3 {
                    food.remove(at: fi)
                    f.eaten += 1
                    nextBreed -= 1.5 // well-fed tanks grow faster
                    bubbles.append(Bubble(x: f.mouthX, y: f.y - 0.5,
                                          phase: Double.random(in: 0...(2 * .pi)),
                                          speed: Double.random(in: 0.2...0.35)))
                    break
                }
            }

            if Double.random(in: 0...1) < 0.008 {
                bubbles.append(Bubble(x: f.mouthX, y: f.y,
                                      phase: Double.random(in: 0...(2 * .pi)),
                                      speed: Double.random(in: 0.15...0.3)))
            }

            if let growAt = f.growAt, now >= growAt {
                f.species = Int.random(in: 1..<allSpecies.count)
                f.speed = Double.random(in: allSpecies[f.species].speed)
                f.growAt = nil
                clampToTank(&f)
            }

            fish[i] = f
        }
    }

    private func nearestFood(for f: Fish) -> Food? {
        food.filter { abs($0.x - f.x) < 28 }
            .min { a, b in
                let da = pow(a.x - f.x, 2) + pow((a.y - f.y) * 2, 2)
                let db = pow(b.x - f.x, 2) + pow((b.y - f.y) * 2, 2)
                return da < db
            }
    }

    private func updateFood(_ now: Double) {
        for i in food.indices {
            if food[i].y < Double(sandRow) {
                food[i].y = min(Double(sandRow), food[i].y + food[i].vy)
            } else if food[i].restingSince == nil {
                food[i].restingSince = now
            }
        }
        food.removeAll { resting in
            if let since = resting.restingSince { return now - since > 10 }
            return false
        }
    }

    private func updateBubbles(_ now: Double) {
        for i in bubbles.indices {
            bubbles[i].y -= bubbles[i].speed
            bubbles[i].x += sin(now * 3 + bubbles[i].phase) * 0.12
        }
        bubbles.removeAll { $0.y <= Double(surfaceRow) + 0.5 || $0.x < 1 || $0.x >= Double(cols - 1) }

        if Double.random(in: 0...1) < 0.15, cols > 8 {
            let x = weeds.randomElement().map { Double($0.x) + Double.random(in: -1...1) }
                ?? Double.random(in: 2...Double(cols - 3))
            bubbles.append(Bubble(x: min(max(2, x), Double(cols - 3)),
                                  y: Double(sandRow - 1),
                                  phase: Double.random(in: 0...(2 * .pi)),
                                  speed: Double.random(in: 0.15...0.35)))
        }
    }

    private func updateJellyfish(_ now: Double) {
        for i in jellyfish.indices {
            var j = jellyfish[i]
            j.vy += j.isContracted(at: now) ? -0.018 : 0.010
            j.vy = max(-0.15, min(0.1, j.vy))
            j.y += j.vy
            j.x += sin(now * 0.4 + j.driftSeed) * 0.06

            let minY = Double(swimMinRow)
            let maxY = Double(max(swimMinRow, swimMaxRow - 1)) // two rows tall
            if j.y < minY { j.y = minY; j.vy = 0.05 }
            if j.y > maxY { j.y = maxY; j.vy = -0.05 }
            j.x = min(max(1, j.x), Double(max(1, cols - 7)))
            jellyfish[i] = j
        }
    }

    private func updateChest(_ now: Double) {
        guard let cx = chestX else { return }

        if now >= chestOpenUntil, now >= chestNextOpen {
            chestOpenUntil = now + Double.random(in: 2...3.5)
            chestNextOpen = now + Double.random(in: 10...18)
            // The lid popping open startles fish loitering near the bottom.
            let center = Double(cx) + 3
            for i in fish.indices where abs(fish[i].x - center) < 12
                && fish[i].y > Double(swimMaxRow - 6) {
                fish[i].dir = fish[i].x < center ? -1 : 1
                fish[i].vy = -0.3
            }
        }

        if now < chestOpenUntil, Double.random(in: 0...1) < 0.5 {
            bubbles.append(Bubble(x: Double(cx) + Double.random(in: 1.5...4.5),
                                  y: Double(sandRow - 3),
                                  phase: Double.random(in: 0...(2 * .pi)),
                                  speed: Double.random(in: 0.2...0.4)))
        }
    }

    // MARK: - Rendering

    func render() -> String {
        guard cols >= 34, rows >= 12 else {
            return ANSI.home + ANSI.clear + ANSI.fg(220)
                + "터미널 창을 조금만 키워주세요! (최소 34x12)" + ANSI.reset
        }

        var grid = [[Cell]](repeating: [Cell](repeating: Cell(), count: cols), count: gridRows)
        let now = self.now

        drawTank(&grid, now)
        drawWeeds(&grid, now)
        drawChest(&grid, now)
        drawFood(&grid)
        drawBubbles(&grid)
        drawJellyfish(&grid, now)
        drawFish(&grid)

        var out = ANSI.home
        var lastColor: UInt8 = 0
        for (r, row) in grid.enumerated() {
            if r > 0 { out += "\r\n" }
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
        }
        out += "\r\n" + statusLine(now) + "\u{1B}[K"
        return out
    }

    private func drawTank(_ grid: inout [[Cell]], _ now: Double) {
        let frame: UInt8 = 30
        for c in 0..<cols {
            grid[0][c] = Cell(ch: "-", color: frame)
            grid[bottomBorderRow][c] = Cell(ch: "-", color: frame)
        }
        for r in 0..<gridRows {
            grid[r][0] = Cell(ch: "|", color: frame)
            grid[r][cols - 1] = Cell(ch: "|", color: frame)
        }
        grid[0][0] = Cell(ch: "+", color: frame)
        grid[0][cols - 1] = Cell(ch: "+", color: frame)
        grid[bottomBorderRow][0] = Cell(ch: "+", color: frame)
        grid[bottomBorderRow][cols - 1] = Cell(ch: "+", color: frame)

        let title = Array(" ~ A Q U A R I U M ~ ")
        if cols > title.count + 4 {
            let start = (cols - title.count) / 2
            for (i, ch) in title.enumerated() {
                grid[0][start + i] = Cell(ch: ch, color: 45)
            }
        }

        for c in 1..<(cols - 1) {
            let wave = sin(Double(c) * 0.45 + now * 2)
            let ch: Character = wave > 0.2 ? "~" : (wave < -0.6 ? "-" : " ")
            grid[surfaceRow][c] = Cell(ch: ch, color: wave > 0.2 ? 45 : 39)
        }

        for c in 1..<(cols - 1) {
            let h = Int((UInt(c) &* 2_654_435_761) % 1000)
            let sandChars: [Character] = [".", ".", "_", ",", ":"]
            let sandColors: [UInt8] = [180, 137, 143]
            grid[sandRow][c] = Cell(ch: sandChars[h % sandChars.count],
                                    color: sandColors[h % sandColors.count])
        }
    }

    private func drawWeeds(_ grid: inout [[Cell]], _ now: Double) {
        for weed in weeds {
            guard weed.x > 0, weed.x < cols - 1 else { continue }
            for i in 0..<weed.height {
                let r = sandRow - 1 - i
                guard r >= swimMinRow else { break }
                let sway = Int(now * 2 + weed.phase) + i
                grid[r][weed.x] = Cell(ch: sway % 2 == 0 ? "(" : ")",
                                       color: i % 2 == 0 ? 28 : 40)
            }
        }
    }

    private func drawChest(_ grid: inout [[Cell]], _ now: Double) {
        guard let cx = chestX else { return }
        let topRow = sandRow - 2, bottomRow = sandRow - 1
        guard topRow >= swimMinRow else { return }

        let isOpen = now < chestOpenUntil
        let top: [Character] = isOpen ? Array("\\****/") : Array(" ____ ")
        let bottom: [Character] = Array("[____]")
        let goldShimmer: [UInt8] = [220, 226, 214]

        for (i, ch) in top.enumerated() where ch != " " {
            let c = cx + i
            guard c > 0, c < cols - 1 else { continue }
            let color: UInt8 = ch == "*" ? goldShimmer[(tick / 2 + i) % goldShimmer.count] : 130
            grid[topRow][c] = Cell(ch: ch, color: color)
        }
        for (i, ch) in bottom.enumerated() {
            let c = cx + i
            guard c > 0, c < cols - 1 else { continue }
            grid[bottomRow][c] = Cell(ch: ch, color: 130)
        }
    }

    private func drawJellyfish(_ grid: inout [[Cell]], _ now: Double) {
        for j in jellyfish {
            let art: [[Character]] = j.isContracted(at: now)
                ? [Array(" (_) "), Array("  |  ")]
                : [Array("(___)"), Array(" )|( ")]
            let bellColor: UInt8 = [183, 189, 177][(tick / 4) % 3] // translucent shimmer
            let startR = Int(j.y.rounded())
            let startC = Int(j.x.rounded())
            for (ri, rowArt) in art.enumerated() {
                let r = startR + ri
                guard r >= swimMinRow, r <= swimMaxRow else { continue }
                for (ci, ch) in rowArt.enumerated() where ch != " " {
                    let c = startC + ci
                    guard c > 0, c < cols - 1 else { continue }
                    grid[r][c] = Cell(ch: ch, color: ri == 0 ? bellColor : 146)
                }
            }
        }
    }

    private func drawFood(_ grid: inout [[Cell]]) {
        for pellet in food {
            let r = Int(pellet.y.rounded()), c = Int(pellet.x.rounded())
            guard r >= swimMinRow, r <= sandRow, c > 0, c < cols - 1 else { continue }
            grid[r][c] = Cell(ch: "*", color: 214)
        }
    }

    private func drawBubbles(_ grid: inout [[Cell]]) {
        for bubble in bubbles {
            let r = Int(bubble.y.rounded()), c = Int(bubble.x.rounded())
            guard r >= swimMinRow, r <= swimMaxRow, c > 0, c < cols - 1 else { continue }
            let depth = bubble.y / Double(max(1, swimMaxRow))
            let ch: Character = depth > 0.66 ? "." : (depth > 0.33 ? "o" : "O")
            grid[r][c] = Cell(ch: ch, color: 117)
        }
    }

    private func drawFish(_ grid: inout [[Cell]]) {
        for f in fish {
            let r = Int(f.y.rounded())
            guard r >= swimMinRow, r <= swimMaxRow else { continue }
            let startC = Int(f.x.rounded())
            for (i, ch) in f.art.enumerated() {
                let c = startC + i
                guard c > 0, c < cols - 1 else { continue }
                let color: UInt8
                if ch == "°" {
                    color = 231
                } else if allSpecies[f.species].striped {
                    color = i % 2 == 0 ? f.color : f.color2
                } else {
                    color = f.color
                }
                grid[r][c] = Cell(ch: ch, color: color)
            }
        }
    }

    private func statusLine(_ now: Double) -> String {
        let elapsed = Int(now - startTime)
        let timeStr = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        let sep = ANSI.fg(240) + "  |  "
        var line = ANSI.fg(51) + " 물고기 \(fish.count)마리"
            + sep + ANSI.fg(214) + "먹이 \(food.count)"
            + sep + ANSI.fg(250) + timeStr
            + sep + ANSI.fg(245) + "[f] 먹이 주기  [q] 종료"
        if now < messageUntil {
            line += ANSI.fg(213) + "   " + message
        }
        return line + ANSI.reset
    }
}
