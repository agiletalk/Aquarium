import AquariumCore
import Foundation

extension Achievements {
    /// CLI: `aquarium --achievements`
    static func printAll() {
        guard let save = SaveStore.load(), !save.fish.isEmpty else {
            print(L10n.statusNoTank)
            return
        }
        let stats = mergedStats(from: save)
        let unlocked = all.filter { isUnlocked($0, stats: stats) }.count
        print(ANSI.fg(226) + L10n.achievementsHeader(unlocked, all.count) + ANSI.reset)
        print("")
        for a in all {
            if isUnlocked(a, stats: stats) {
                print(ANSI.fg(84) + "  \u{2714} \(a.icon) \(a.name)"
                      + ANSI.fg(244) + "  — \(a.desc)" + ANSI.reset)
            } else {
                let have = stats[a.stat] ?? 0
                print(ANSI.fg(240) + "  \u{00B7} \(a.icon) \(a.name)  (\(have)/\(a.threshold))" + ANSI.reset)
            }
        }
    }
}
