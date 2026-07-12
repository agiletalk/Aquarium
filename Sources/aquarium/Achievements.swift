import Foundation

struct Achievement {
    let id: String
    let icon: String
    let stat: String
    let threshold: Int
    let ko: String
    let en: String
    let koDesc: String
    let enDesc: String

    var name: String { L10n.isKorean ? ko : en }
    var desc: String { L10n.isKorean ? koDesc : enDesc }
}

enum Achievements {
    static let all: [Achievement] = [
    Achievement(id: "born_1", icon: "🐣", stat: "born", threshold: 1, ko: "첫 탄생", en: "First Born", koDesc: "아기 1마리 탄생", enDesc: "1 babies born"),
    Achievement(id: "born_5", icon: "🐣", stat: "born", threshold: 5, ko: "유치원", en: "Nursery", koDesc: "아기 5마리 탄생", enDesc: "5 babies born"),
    Achievement(id: "born_10", icon: "🐣", stat: "born", threshold: 10, ko: "대가족", en: "Big Family", koDesc: "아기 10마리 탄생", enDesc: "10 babies born"),
    Achievement(id: "born_25", icon: "🐣", stat: "born", threshold: 25, ko: "번식왕", en: "Breeder", koDesc: "아기 25마리 탄생", enDesc: "25 babies born"),
    Achievement(id: "born_50", icon: "🐣", stat: "born", threshold: 50, ko: "인구 폭발", en: "Baby Boom", koDesc: "아기 50마리 탄생", enDesc: "50 babies born"),
    Achievement(id: "born_100", icon: "🐣", stat: "born", threshold: 100, ko: "어항 원장님", en: "Headmaster", koDesc: "아기 100마리 탄생", enDesc: "100 babies born"),
    Achievement(id: "born_250", icon: "🐣", stat: "born", threshold: 250, ko: "생명의 요람", en: "Cradle of Life", koDesc: "아기 250마리 탄생", enDesc: "250 babies born"),
    Achievement(id: "born_500", icon: "🐣", stat: "born", threshold: 500, ko: "창조주", en: "The Creator", koDesc: "아기 500마리 탄생", enDesc: "500 babies born"),
    Achievement(id: "born_1000", icon: "🐣", stat: "born", threshold: 1000, ko: "무한 증식", en: "Endless Bloom", koDesc: "아기 1000마리 탄생", enDesc: "1000 babies born"),
    Achievement(id: "fish_10", icon: "🐠", stat: "fish", threshold: 10, ko: "북적북적", en: "Bustling", koDesc: "동시에 10마리 보유", enDesc: "10 fish at once"),
    Achievement(id: "fish_20", icon: "🐠", stat: "fish", threshold: 20, ko: "대군", en: "Legion", koDesc: "동시에 20마리 보유", enDesc: "20 fish at once"),
    Achievement(id: "fish_30", icon: "🐠", stat: "fish", threshold: 30, ko: "만석 직전", en: "Nearly Full", koDesc: "동시에 30마리 보유", enDesc: "30 fish at once"),
    Achievement(id: "fish_40", icon: "🐠", stat: "fish", threshold: 40, ko: "만원 어항", en: "Full House", koDesc: "동시에 40마리 보유", enDesc: "40 fish at once"),
    Achievement(id: "fed_10", icon: "🍚", stat: "fed", threshold: 10, ko: "첫 한 끼", en: "First Meal", koDesc: "먹이 10개 뿌리기", enDesc: "10 pellets sprinkled"),
    Achievement(id: "fed_50", icon: "🍚", stat: "fed", threshold: 50, ko: "급식 시작", en: "Feeding Time", koDesc: "먹이 50개 뿌리기", enDesc: "50 pellets sprinkled"),
    Achievement(id: "fed_100", icon: "🍚", stat: "fed", threshold: 100, ko: "밥 주는 손", en: "The Feeding Hand", koDesc: "먹이 100개 뿌리기", enDesc: "100 pellets sprinkled"),
    Achievement(id: "fed_500", icon: "🍚", stat: "fed", threshold: 500, ko: "사료 도매상", en: "Bulk Feeder", koDesc: "먹이 500개 뿌리기", enDesc: "500 pellets sprinkled"),
    Achievement(id: "fed_1000", icon: "🍚", stat: "fed", threshold: 1000, ko: "진수성찬", en: "Great Feast", koDesc: "먹이 1000개 뿌리기", enDesc: "1000 pellets sprinkled"),
    Achievement(id: "fed_5000", icon: "🍚", stat: "fed", threshold: 5000, ko: "먹이 폭포", en: "Food Falls", koDesc: "먹이 5000개 뿌리기", enDesc: "5000 pellets sprinkled"),
    Achievement(id: "fed_10000", icon: "🍚", stat: "fed", threshold: 10000, ko: "무한 뷔페", en: "Infinite Buffet", koDesc: "먹이 10000개 뿌리기", enDesc: "10000 pellets sprinkled"),
    Achievement(id: "feedActions_1", icon: "🥄", stat: "feedActions", threshold: 1, ko: "첫 먹이", en: "First Sprinkle", koDesc: "먹이 주기 1회", enDesc: "fed 1 times"),
    Achievement(id: "feedActions_10", icon: "🥄", stat: "feedActions", threshold: 10, ko: "단골 사육사", en: "Regular Keeper", koDesc: "먹이 주기 10회", enDesc: "fed 10 times"),
    Achievement(id: "feedActions_50", icon: "🥄", stat: "feedActions", threshold: 50, ko: "성실한 집사", en: "Diligent Caretaker", koDesc: "먹이 주기 50회", enDesc: "fed 50 times"),
    Achievement(id: "feedActions_100", icon: "🥄", stat: "feedActions", threshold: 100, ko: "먹이 요정", en: "Feeding Fairy", koDesc: "먹이 주기 100회", enDesc: "fed 100 times"),
    Achievement(id: "shrimp_1", icon: "🦐", stat: "shrimp", threshold: 1, ko: "사냥 개시", en: "Let the Hunt Begin", koDesc: "새우 1마리 방류", enDesc: "1 shrimp released"),
    Achievement(id: "shrimp_10", icon: "🦐", stat: "shrimp", threshold: 10, ko: "새우 파티", en: "Shrimp Party", koDesc: "새우 10마리 방류", enDesc: "10 shrimp released"),
    Achievement(id: "shrimp_50", icon: "🦐", stat: "shrimp", threshold: 50, ko: "생태 사육사", en: "Live Feeder", koDesc: "새우 50마리 방류", enDesc: "50 shrimp released"),
    Achievement(id: "shrimp_100", icon: "🦐", stat: "shrimp", threshold: 100, ko: "새우 양식장", en: "Shrimp Farm", koDesc: "새우 100마리 방류", enDesc: "100 shrimp released"),
    Achievement(id: "shrimpEaten_1", icon: "🎣", stat: "shrimpEaten", threshold: 1, ko: "첫 사냥 성공", en: "First Catch", koDesc: "새우 1마리 포식", enDesc: "1 shrimp eaten"),
    Achievement(id: "shrimpEaten_10", icon: "🎣", stat: "shrimpEaten", threshold: 10, ko: "사냥 본능", en: "Hunting Instinct", koDesc: "새우 10마리 포식", enDesc: "10 shrimp eaten"),
    Achievement(id: "shrimpEaten_50", icon: "🎣", stat: "shrimpEaten", threshold: 50, ko: "포식자", en: "Predator", koDesc: "새우 50마리 포식", enDesc: "50 shrimp eaten"),
    Achievement(id: "shrimpEaten_100", icon: "🎣", stat: "shrimpEaten", threshold: 100, ko: "먹이사슬 정점", en: "Apex Predator", koDesc: "새우 100마리 포식", enDesc: "100 shrimp eaten"),
    Achievement(id: "touch_1", icon: "✋", stat: "touch", threshold: 1, ko: "첫 교감", en: "First Touch", koDesc: "물고기 1번 만지기", enDesc: "petted fish 1 times"),
    Achievement(id: "touch_10", icon: "✋", stat: "touch", threshold: 10, ko: "낯가림 극복", en: "Breaking the Ice", koDesc: "물고기 10번 만지기", enDesc: "petted fish 10 times"),
    Achievement(id: "touch_50", icon: "✋", stat: "touch", threshold: 50, ko: "친해지는 중", en: "Getting Close", koDesc: "물고기 50번 만지기", enDesc: "petted fish 50 times"),
    Achievement(id: "touch_100", icon: "✋", stat: "touch", threshold: 100, ko: "물고기 친구", en: "Fish Whisperer", koDesc: "물고기 100번 만지기", enDesc: "petted fish 100 times"),
    Achievement(id: "touch_500", icon: "✋", stat: "touch", threshold: 500, ko: "만짐 장인", en: "Master Petter", koDesc: "물고기 500번 만지기", enDesc: "petted fish 500 times"),
    Achievement(id: "touch_1000", icon: "✋", stat: "touch", threshold: 1000, ko: "어항의 손길", en: "Hand of the Tank", koDesc: "물고기 1000번 만지기", enDesc: "petted fish 1000 times"),
    Achievement(id: "touchNight_1", icon: "🌙", stat: "touchNight", threshold: 1, ko: "야행성 교감", en: "Night Touch", koDesc: "밤에 1번 만지기", enDesc: "petted 1 times at night"),
    Achievement(id: "touchNight_10", icon: "🌙", stat: "touchNight", threshold: 10, ko: "자장가 손길", en: "Lullaby Hand", koDesc: "밤에 10번 만지기", enDesc: "petted 10 times at night"),
    Achievement(id: "focus_1", icon: "🍅", stat: "focus", threshold: 1, ko: "첫 집중", en: "First Focus", koDesc: "집중 세션 1회 완료", enDesc: "1 focus sessions"),
    Achievement(id: "focus_5", icon: "🍅", stat: "focus", threshold: 5, ko: "뽀모도로 입문", en: "Pomodoro Rookie", koDesc: "집중 세션 5회 완료", enDesc: "5 focus sessions"),
    Achievement(id: "focus_10", icon: "🍅", stat: "focus", threshold: 10, ko: "집중 모드", en: "In the Zone", koDesc: "집중 세션 10회 완료", enDesc: "10 focus sessions"),
    Achievement(id: "focus_25", icon: "🍅", stat: "focus", threshold: 25, ko: "몰입러", en: "Deep Worker", koDesc: "집중 세션 25회 완료", enDesc: "25 focus sessions"),
    Achievement(id: "focus_50", icon: "🍅", stat: "focus", threshold: 50, ko: "집중의 대가", en: "Focus Master", koDesc: "집중 세션 50회 완료", enDesc: "50 focus sessions"),
    Achievement(id: "focus_100", icon: "🍅", stat: "focus", threshold: 100, ko: "생산성 괴물", en: "Productivity Beast", koDesc: "집중 세션 100회 완료", enDesc: "100 focus sessions"),
    Achievement(id: "focus_250", icon: "🍅", stat: "focus", threshold: 250, ko: "시간의 지배자", en: "Time Lord", koDesc: "집중 세션 250회 완료", enDesc: "250 focus sessions"),
    Achievement(id: "commits_1", icon: "💚", stat: "commits", threshold: 1, ko: "첫 커밋 밥", en: "First Commit Feast", koDesc: "커밋 보상 1회", enDesc: "1 commit rewards"),
    Achievement(id: "commits_10", icon: "💚", stat: "commits", threshold: 10, ko: "커밋 사육사", en: "Commit Keeper", koDesc: "커밋 보상 10회", enDesc: "10 commit rewards"),
    Achievement(id: "commits_50", icon: "💚", stat: "commits", threshold: 50, ko: "푸시 앤 피드", en: "Push & Feed", koDesc: "커밋 보상 50회", enDesc: "50 commit rewards"),
    Achievement(id: "commits_100", icon: "💚", stat: "commits", threshold: 100, ko: "커밋 백단", en: "Century Committer", koDesc: "커밋 보상 100회", enDesc: "100 commit rewards"),
    Achievement(id: "commits_500", icon: "💚", stat: "commits", threshold: 500, ko: "초록 잔디", en: "Green Graph", koDesc: "커밋 보상 500회", enDesc: "500 commit rewards"),
    Achievement(id: "commits_1000", icon: "💚", stat: "commits", threshold: 1000, ko: "커밋 머신", en: "Commit Machine", koDesc: "커밋 보상 1000회", enDesc: "1000 commit rewards"),
    Achievement(id: "commits_5000", icon: "💚", stat: "commits", threshold: 5000, ko: "깃 신", en: "Git Deity", koDesc: "커밋 보상 5000회", enDesc: "5000 commit rewards"),
    Achievement(id: "whale_1", icon: "🐋", stat: "whale", threshold: 1, ko: "고래다!", en: "Thar She Blows", koDesc: "고래 1회 목격", enDesc: "whale seen 1x"),
    Achievement(id: "whale_5", icon: "🐋", stat: "whale", threshold: 5, ko: "고래 관측자", en: "Whale Watcher", koDesc: "고래 5회 목격", enDesc: "whale seen 5x"),
    Achievement(id: "whale_10", icon: "🐋", stat: "whale", threshold: 10, ko: "고래 친구", en: "Whale Friend", koDesc: "고래 10회 목격", enDesc: "whale seen 10x"),
    Achievement(id: "whale_25", icon: "🐋", stat: "whale", threshold: 25, ko: "고래의 벗", en: "Whale Whisperer", koDesc: "고래 25회 목격", enDesc: "whale seen 25x"),
    Achievement(id: "turtle_1", icon: "🐢", stat: "turtle", threshold: 1, ko: "거북이 손님", en: "Turtle Guest", koDesc: "거북이 1회 목격", enDesc: "turtle seen 1x"),
    Achievement(id: "turtle_5", icon: "🐢", stat: "turtle", threshold: 5, ko: "거북이 단골", en: "Turtle Regular", koDesc: "거북이 5회 목격", enDesc: "turtle seen 5x"),
    Achievement(id: "turtle_10", icon: "🐢", stat: "turtle", threshold: 10, ko: "느긋한 우정", en: "Slow Friendship", koDesc: "거북이 10회 목격", enDesc: "turtle seen 10x"),
    Achievement(id: "turtle_25", icon: "🐢", stat: "turtle", threshold: 25, ko: "거북선", en: "Turtle Fleet", koDesc: "거북이 25회 목격", enDesc: "turtle seen 25x"),
    Achievement(id: "octopus_1", icon: "🐙", stat: "octopus", threshold: 1, ko: "먹물 세례", en: "Ink Splash", koDesc: "문어 1회 목격", enDesc: "octopus seen 1x"),
    Achievement(id: "octopus_5", icon: "🐙", stat: "octopus", threshold: 5, ko: "문어 관찰", en: "Octopus Sighting", koDesc: "문어 5회 목격", enDesc: "octopus seen 5x"),
    Achievement(id: "octopus_10", icon: "🐙", stat: "octopus", threshold: 10, ko: "여덟 다리 친구", en: "Eight-Armed Friend", koDesc: "문어 10회 목격", enDesc: "octopus seen 10x"),
    Achievement(id: "octopus_25", icon: "🐙", stat: "octopus", threshold: 25, ko: "심해의 지성", en: "Deep Intellect", koDesc: "문어 25회 목격", enDesc: "octopus seen 25x"),
    Achievement(id: "visitors_1", icon: "🚪", stat: "visitors", threshold: 1, ko: "첫 손님", en: "First Guest", koDesc: "손님 1회 방문", enDesc: "1 visitors total"),
    Achievement(id: "visitors_10", icon: "🚪", stat: "visitors", threshold: 10, ko: "손님맞이", en: "Welcoming Host", koDesc: "손님 10회 방문", enDesc: "10 visitors total"),
    Achievement(id: "visitors_50", icon: "🚪", stat: "visitors", threshold: 50, ko: "인기 어항", en: "Popular Tank", koDesc: "손님 50회 방문", enDesc: "50 visitors total"),
    Achievement(id: "visitors_100", icon: "🚪", stat: "visitors", threshold: 100, ko: "명소", en: "Landmark Tank", koDesc: "손님 100회 방문", enDesc: "100 visitors total"),
    Achievement(id: "days_1", icon: "📅", stat: "days", threshold: 1, ko: "어항 개장", en: "Grand Opening", koDesc: "어항 1일째", enDesc: "tank day 1"),
    Achievement(id: "days_3", icon: "📅", stat: "days", threshold: 3, ko: "삼일째", en: "Day Three", koDesc: "어항 3일째", enDesc: "tank day 3"),
    Achievement(id: "days_7", icon: "📅", stat: "days", threshold: 7, ko: "일주일", en: "One Week", koDesc: "어항 7일째", enDesc: "tank day 7"),
    Achievement(id: "days_14", icon: "📅", stat: "days", threshold: 14, ko: "격주 사육", en: "Two Weeks", koDesc: "어항 14일째", enDesc: "tank day 14"),
    Achievement(id: "days_30", icon: "📅", stat: "days", threshold: 30, ko: "한 달 집사", en: "One Month", koDesc: "어항 30일째", enDesc: "tank day 30"),
    Achievement(id: "days_60", icon: "📅", stat: "days", threshold: 60, ko: "두 달", en: "Two Months", koDesc: "어항 60일째", enDesc: "tank day 60"),
    Achievement(id: "days_100", icon: "📅", stat: "days", threshold: 100, ko: "백일잔치", en: "Hundred Days", koDesc: "어항 100일째", enDesc: "tank day 100"),
    Achievement(id: "days_200", icon: "📅", stat: "days", threshold: 200, ko: "반년지기", en: "Half a Year", koDesc: "어항 200일째", enDesc: "tank day 200"),
    Achievement(id: "days_365", icon: "📅", stat: "days", threshold: 365, ko: "어항 1주년", en: "One Year", koDesc: "어항 365일째", enDesc: "tank day 365"),
    Achievement(id: "species_3", icon: "🌈", stat: "species", threshold: 3, ko: "다양성", en: "Variety", koDesc: "3종 동시 보유", enDesc: "3 species at once"),
    Achievement(id: "species_5", icon: "🌈", stat: "species", threshold: 5, ko: "다섯 빛깔", en: "Five Colors", koDesc: "5종 동시 보유", enDesc: "5 species at once"),
    Achievement(id: "species_8", icon: "🌈", stat: "species", threshold: 8, ko: "수족관", en: "Aquarist", koDesc: "8종 동시 보유", enDesc: "8 species at once"),
    Achievement(id: "species_10", icon: "🌈", stat: "species", threshold: allSpecies.count - 1, ko: "도감 완성", en: "Full Species Dex", koDesc: "\(allSpecies.count - 1)종 동시 보유", enDesc: "all \(allSpecies.count - 1) species at once"),
    Achievement(id: "chest_1", icon: "💰", stat: "chest", threshold: 1, ko: "보물 발견", en: "Treasure Spotted", koDesc: "보물상자 1회 열림", enDesc: "chest opened 1x"),
    Achievement(id: "chest_10", icon: "💰", stat: "chest", threshold: 10, ko: "보물 사냥꾼", en: "Treasure Hunter", koDesc: "보물상자 10회 열림", enDesc: "chest opened 10x"),
    Achievement(id: "chest_50", icon: "💰", stat: "chest", threshold: 50, ko: "해적왕", en: "Pirate King", koDesc: "보물상자 50회 열림", enDesc: "chest opened 50x"),
    Achievement(id: "music_1", icon: "🎵", stat: "music", threshold: 1, ko: "첫 BGM", en: "First Tune", koDesc: "음악 1회 재생", enDesc: "music played 1x"),
    Achievement(id: "music_10", icon: "🎵", stat: "music", threshold: 10, ko: "어항 DJ", en: "Tank DJ", koDesc: "음악 10회 재생", enDesc: "music played 10x"),
    Achievement(id: "nights_1", icon: "🌌", stat: "nights", threshold: 1, ko: "첫 밤", en: "First Night", koDesc: "밤 1회 맞이", enDesc: "1 nights"),
    Achievement(id: "nights_10", icon: "🌌", stat: "nights", threshold: 10, ko: "야간 근무", en: "Night Shift", koDesc: "밤 10회 맞이", enDesc: "10 nights"),
    Achievement(id: "nights_50", icon: "🌌", stat: "nights", threshold: 50, ko: "불면의 어항", en: "Sleepless Tank", koDesc: "밤 50회 맞이", enDesc: "50 nights"),
    Achievement(id: "launches_1", icon: "🚀", stat: "launches", threshold: 1, ko: "첫 방문", en: "First Visit", koDesc: "어항 1회 실행", enDesc: "opened 1 times"),
    Achievement(id: "launches_10", icon: "🚀", stat: "launches", threshold: 10, ko: "단골 방문객", en: "Regular Visitor", koDesc: "어항 10회 실행", enDesc: "opened 10 times"),
    Achievement(id: "launches_50", icon: "🚀", stat: "launches", threshold: 50, ko: "매일의 어항", en: "Daily Ritual", koDesc: "어항 50회 실행", enDesc: "opened 50 times"),
    Achievement(id: "launches_100", icon: "🚀", stat: "launches", threshold: 100, ko: "어항 중독", en: "Tank Addict", koDesc: "어항 100회 실행", enDesc: "opened 100 times"),
    Achievement(id: "cards_1", icon: "🖼️", stat: "cards", threshold: 1, ko: "첫 명함", en: "First Card", koDesc: "명함 1회 생성", enDesc: "1 cards made"),
    Achievement(id: "cards_5", icon: "🖼️", stat: "cards", threshold: 5, ko: "자랑쟁이", en: "Show-off", koDesc: "명함 5회 생성", enDesc: "5 cards made"),
    Achievement(id: "meals_100", icon: "🍽️", stat: "meals", threshold: 100, ko: "잘 먹는 어항", en: "Well-Fed Tank", koDesc: "물고기 식사 100회", enDesc: "100 fish meals"),
    Achievement(id: "meals_1000", icon: "🍽️", stat: "meals", threshold: 1000, ko: "대식가 군단", en: "Legion of Gluttons", koDesc: "물고기 식사 1000회", enDesc: "1000 fish meals"),
    Achievement(id: "meals_10000", icon: "🍽️", stat: "meals", threshold: 10000, ko: "밑 빠진 어항", en: "Bottomless Tank", koDesc: "물고기 식사 10000회", enDesc: "10000 fish meals"),
    Achievement(id: "morphs_1", icon: "✨", stat: "morphs", threshold: 1, ko: "첫 변이", en: "First Morph", koDesc: "희귀 물고기 1마리", enDesc: "1 rare fish"),
    Achievement(id: "morphs_5", icon: "✨", stat: "morphs", threshold: 5, ko: "희귀 애호가", en: "Rarity Fan", koDesc: "희귀 물고기 5마리", enDesc: "5 rare fish"),
    Achievement(id: "morphs_15", icon: "✨", stat: "morphs", threshold: 15, ko: "변이 수집가", en: "Morph Collector", koDesc: "희귀 물고기 15마리", enDesc: "15 rare fish"),
    Achievement(id: "morphs_50", icon: "✨", stat: "morphs", threshold: 50, ko: "돌연변이 마스터", en: "Mutation Master", koDesc: "희귀 물고기 50마리", enDesc: "50 rare fish"),
    Achievement(id: "morphKinds_4", icon: "🌟", stat: "morphKinds", threshold: 4, ko: "전설 컬렉션", en: "All That Glitters", koDesc: "무지개·발광·금빛·칠흑 동시 보유", enDesc: "own all 4 morphs at once"),
    Achievement(id: "personalityKinds_5", icon: "🎭", stat: "personalityKinds", threshold: 5, ko: "만인의 어항", en: "Full Spectrum", koDesc: "성격 5종 동시 보유", enDesc: "all 5 personalities at once"),
    ]

    /// 저장 상태에서 업적 판정용 통계를 계산한다 (카운터 + 파생값 병합).
    static func mergedStats(from save: SaveState) -> [String: Int] {
        var m = save.stats ?? [:]
        m["fish"] = save.fish.count
        m["maxFish"] = max(m["maxFish"] ?? 0, save.fish.count)
        let days = max(1, Int((Date().timeIntervalSince1970 - save.tankBornAt) / 86400) + 1)
        m["days"] = days
        m["species"] = Set(save.fish.map(\.species).filter { $0 > 0 }).count
        m["focus"] = save.focusDone ?? 0
        m["commits"] = save.commitRewards ?? 0
        let whale = save.visitorSeen?["whale"] ?? 0
        let turtle = save.visitorSeen?["turtle"] ?? 0
        let octopus = save.visitorSeen?["octopus"] ?? 0
        m["whale"] = whale; m["turtle"] = turtle; m["octopus"] = octopus
        m["visitors"] = whale + turtle + octopus
        m["morphKinds"] = Set(save.fish.compactMap { $0.morph }.filter { $0 > 0 }).count
        m["personalityKinds"] = Set(save.fish.compactMap { $0.personality }).count
        // 진화 누적 카운터와 현재 보유 희귀 수 중 큰 값 (입양받은 희귀도 인정)
        let rareNow = save.fish.filter { ($0.morph ?? 0) > 0 }.count
        m["morphs"] = max(m["morphs"] ?? 0, rareNow)
        return m
    }

    static func isUnlocked(_ a: Achievement, stats: [String: Int]) -> Bool {
        (stats[a.stat] ?? 0) >= a.threshold
    }

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
