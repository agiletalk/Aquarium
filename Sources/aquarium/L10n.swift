import Foundation

/// Language selection: AQUARIUM_LANG env > LC_ALL/LC_MESSAGES/LANG > macOS AppleLocale > English.
enum L10n {
    static let isKorean: Bool = {
        let env = ProcessInfo.processInfo.environment
        if let forced = env["AQUARIUM_LANG"]?.lowercased() {
            if forced.hasPrefix("ko") { return true }
            if forced.hasPrefix("en") { return false }
        }
        for key in ["LC_ALL", "LC_MESSAGES", "LANG"] {
            if let value = env[key]?.lowercased(), !value.isEmpty {
                return value.hasPrefix("ko")
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "-g", "AppleLocale"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        if (try? process.run()) != nil {
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return output.lowercased().hasPrefix("ko")
        }
        return false
    }()

    private static func t(_ ko: String, _ en: String) -> String { isKorean ? ko : en }

    // MARK: - Fish names

    static let fishNames: [String] = isKorean
        ? ["방울이", "통통이", "쏜살이", "반짝이", "초롱이", "몽실이", "뽀글이", "살랑이",
           "여울이", "물결이", "미르", "파랑이", "노랑이", "분홍이", "산호", "진주",
           "소라", "새벽이", "노을이", "별이", "달이", "구름이", "이슬이", "방긋이",
           "날쌘이", "느긋이", "용용이", "꼬물이", "꿈틀이", "코랄", "아쿠아", "바다",
           "하늘이", "은빛이", "금빛이", "무지개", "솜사탕", "젤리", "푸딩", "모카"]
        : ["Bubbles", "Splash", "Finn", "Coral", "Pearl", "Sunny", "Goldie", "Luna",
           "Marble", "Pebble", "Waves", "Misty", "Echo", "Dot", "Jet", "Blue",
           "Mango", "Kiwi", "Peach", "Berry", "Comet", "Star", "Cloud", "Dewy",
           "Twinkle", "Dash", "Wiggles", "Squirt", "Coco", "Mocha", "Jelly", "Pudding",
           "Candy", "Noodle", "Sprout", "Ripple", "Glimmer", "Breeze", "Sandy", "Ollie"]

    // MARK: - Personality & mood (성격/기분)

    static func personalityName(_ p: Personality) -> String {
        switch p {
        case .shy: return t("소심한", "Shy")
        case .greedy: return t("먹보", "Greedy")
        case .playful: return t("장난꾸러기", "Playful")
        case .lazy: return t("느긋한", "Lazy")
        case .bold: return t("대담한", "Bold")
        }
    }

    /// 도감용 짧은 라벨 (2자 = 4폭)
    static func personalityLabel(_ p: Personality) -> String {
        switch p {
        case .shy: return t("소심", "shy")
        case .greedy: return t("먹보", "eat")
        case .playful: return t("장난", "fun")
        case .lazy: return t("느림", "laz")
        case .bold: return t("대담", "bld")
        }
    }

    /// 성격/기분을 반영한 터치 반응
    static func touchedBy(_ name: String, personality: Personality, mood: Mood) -> String {
        let o = objectParticle(name)
        if isKorean {
            switch mood {
            case .sleepy: return "자던 \(name)\(o) 깨웠어요! 🥱"
            case .eating: return "밥 먹던 \(name)\(o) 방해했어요!"
            case .idle:
                switch personality {
                case .shy: return "소심한 \(name)\(o) 만지자 화들짝 달아났어요!"
                case .greedy: return "먹보 \(name)\(o) 만졌어요 — 먹이인 줄 알았나 봐요!"
                case .playful: return "장난꾸러기 \(name)\(o) 만지니 신나서 뱅글뱅글!"
                case .lazy: return "느긋한 \(name)\(o) 만졌어요 — 별로 놀라지도 않네요."
                case .bold: return "대담한 \(name)\(o) 만졌지만 시큰둥해요."
                }
            }
        } else {
            switch mood {
            case .sleepy: return "You woke up \(name)! 🥱"
            case .eating: return "You interrupted \(name)'s meal!"
            case .idle:
                switch personality {
                case .shy: return "Shy \(name) darts away, startled!"
                case .greedy: return "Greedy \(name) thought you were food!"
                case .playful: return "Playful \(name) spins with delight!"
                case .lazy: return "Lazy \(name) barely reacts."
                case .bold: return "Bold \(name) shrugs it off."
                }
            }
        }
    }

    // MARK: - Rare morphs (희귀 변종)

    static func morphName(_ morph: Morph) -> String {
        switch morph {
        case .normal: return t("보통", "Normal")
        case .rainbow: return t("무지개", "Rainbow")
        case .glowing: return t("발광", "Glowing")
        case .golden: return t("금빛", "Golden")
        case .shadow: return t("칠흑", "Shadow")
        }
    }
    static func evolved(_ name: String, _ morphName: String) -> String {
        isKorean ? "✨ \(name)\(subjectParticle(name)) \(morphName) 물고기로 진화했어요!"
                 : "✨ \(name) evolved into a \(morphName) fish!"
    }
    static func grewRare(_ name: String, _ morphName: String) -> String {
        isKorean ? "✨ 아기 \(name)\(subjectParticle(name)) \(morphName) 물고기로 자랐어요!"
                 : "✨ Baby \(name) grew into a \(morphName) fish!"
    }
    static func cardRare(_ n: Int) -> String { t("✨ 희귀 물고기 \(n)마리", "✨ \(n) rare fish") }

    // MARK: - Tank messages

    static var foodSprinkled: String { t("먹이를 뿌렸어요! 물고기들이 몰려듭니다~", "Food sprinkled! Here they come~") }
    static var shrimpReleased: String { t("브라인슈림프를 풀었어요! 사냥 개시!", "Brine shrimp released — the hunt is on!") }

    static func babyBorn(_ name: String, count: Int) -> String {
        isKorean
            ? "아기 \(name)\(subjectParticle(name)) 태어났어요! (\(count)마리)"
            : "Baby \(name) was born! (\(count) fish)"
    }

    static func welcomeBack(count: Int) -> String {
        t("어항에 돌아오신 걸 환영해요! (물고기 \(count)마리)", "Welcome back to your tank! (\(count) fish)")
    }

    static func offlineBirths(_ born: Int, total: Int) -> String {
        t("다녀오신 사이 물고기 \(born)마리가 태어났어요! (\(total)마리)",
          "\(born) fish were born while you were away! (\(total) total)")
    }

    static func touched(_ name: String) -> String {
        isKorean ? "\(name)\(objectParticle(name)) 만졌어요!" : "You touched \(name)!"
    }

    static func lightingAuto(isNight: Bool) -> String {
        t("조명: 자동 (지금은 \(isNight ? "밤" : "낮"))", "Lights: auto (currently \(isNight ? "night" : "day"))")
    }
    static var lightingNight: String { t("조명: 밤", "Lights: night") }
    static var lightingDay: String { t("조명: 낮", "Lights: day") }

    static var whalePassing: String { t("저 멀리 고래가 지나가요…", "A whale is passing by in the distance…") }
    static var turtleVisiting: String { t("거북이가 놀러 왔어요!", "A sea turtle came to visit!") }
    static var octopusAppeared: String { t("문어가 나타났어요!", "An octopus appeared!") }
    static var octopusVanished: String { t("문어가 먹물을 뿜고 사라졌어요!", "The octopus squirted ink and vanished!") }

    static var musicOn: String { t("음악을 켰어요 (DOS 감성 칩튠)", "Music on (DOS-era chiptunes)") }
    static var musicOff: String { t("음악을 껐어요", "Music off") }
    static var musicFailed: String { t("음악을 재생할 수 없어요 (오디오 장치를 못 찾음)", "Can't play music (no audio device found)") }
    static func nowPlaying(_ title: String) -> String { t("♪ 지금 나오는 곡: \(title)", "♪ Now playing: \(title)") }

    // MARK: - Focus (pomodoro)

    static func focusStarted(_ minutes: Int) -> String {
        t("집중 시작! \(minutes)분 — 물고기들이 응원하고 있어요", "Focus started! \(minutes) min — the fish are rooting for you")
    }
    static var focusCancelled: String { t("집중을 중단했어요", "Focus cancelled") }
    static func focusComplete(_ total: Int) -> String {
        t("집중 완료! 보상으로 먹이 대잔치를 열었어요 (누적 \(total)회)",
          "Focus complete! Feast time as a reward (total \(total))")
    }
    static func statusFocus(_ time: String) -> String { t("집중 \(time)", "focus \(time)") }
    static func rosterFocus(_ n: Int) -> String { t("집중 기록   \(n)회 완료", "Focus   \(n) sessions done") }

    // MARK: - Tank capacity

    static func tankFull(_ max: Int) -> String {
        t("어항이 가득 찼어요! (최대 \(max)마리)", "The tank is full! (max \(max) fish)")
    }
    static var statusTankFull: String { t("어항이 가득 찼어요!", "the tank is full!") }

    // MARK: - Status bar

    static func statusFish(_ n: Int) -> String { t("물고기 \(n)마리", "\(n) fish") }
    static func statusFood(_ n: Int) -> String { t("먹이 \(n)", "food \(n)") }
    static func statusDay(_ days: Int, _ time: String) -> String { t("\(days)일째 \(time)", "day \(days) · \(time)") }
    static func modeLabel(auto: Bool, night: Bool) -> String {
        if auto { return t(night ? "밤·자동" : "낮·자동", night ? "night·auto" : "day·auto") }
        return t(night ? "밤" : "낮", night ? "night" : "day")
    }
    static var helpLine: String {
        t("[f] 먹이  [g] 생먹이  [p] 집중  [i] 도감  [b] 편지함  [s] 후원  [n] 조명  [m] 음악  [q] 종료",
          "[f] feed  [g] live food  [p] focus  [i] log  [b] mail  [s] support  [n] lights  [m] music  [q] quit")
    }
    static var enlargeTerminal: String { t("터미널 창을 조금만 키워주세요! (최소 34x12)", "Please enlarge the terminal! (min 34x12)") }

    // MARK: - Roster panel

    static func rosterTitle(_ n: Int) -> String { t("[ 우리 어항 도감 · \(n)마리 ]", "[ Tank Log · \(n) fish ]") }
    static var rosterToday: String { t("오늘", "today") }
    static func rosterDays(_ d: Int) -> String { t("\(d)일째", "day \(d)") }
    static func rosterEaten(_ n: Int) -> String { t("먹이 \(n)", "fed \(n)") }
    static func rosterMore(_ n: Int) -> String { t("…외 \(n)마리", "…and \(n) more") }
    static func rosterVisitors(whale: Int, turtle: Int, octopus: Int) -> String {
        t("손님 기록   고래 \(whale) · 거북이 \(turtle) · 문어 \(octopus)",
          "Visitors   whale \(whale) · turtle \(turtle) · octopus \(octopus)")
    }
    static var rosterEnlarge: String { t("도감을 보려면 창을 키워주세요", "Enlarge the window to see the log") }

    // MARK: - CLI

    static var statusNoTank: String {
        t("><> 아직 어항이 없어요 — aquarium 을 실행해 물고기를 만나보세요!",
          "><> No tank yet — run aquarium to meet your fish!")
    }
    static var statusBabyWaiting: String { t("아기가 기다리고 있어요!", "a baby is waiting!") }
    static func statusNextBirthMinutes(_ m: Int) -> String { t("다음 탄생까지 \(m)분", "next birth in \(m)m") }
    static func statusNextBirthSeconds(_ s: Int) -> String { t("다음 탄생까지 \(s)초", "next birth in \(s)s") }
    static func statusLine(count: Int, days: Int, breed: String) -> String {
        t("><> \(count)마리 · \(days)일째 · \(breed)", "><> \(count) fish · day \(days) · \(breed)")
    }
    static var goodbye: String {
        t("어항을 저장했어요. 다음에 또 만나요! ><>  <><", "Tank saved. See you next time! ><>  <><")
    }
    static func unknownOption(_ option: String) -> String {
        t("알 수 없는 옵션: \(option)\n--help 를 참고하세요.", "Unknown option: \(option)\nSee --help.")
    }
    static var helpText: String {
        isKorean
            ? """
            aquarium — 터미널 속 힐링 ASCII 어항

            사용법:
              aquarium              어항 실행
              aquarium --focus [분]  뽀모도로 집중 모드로 시작 (기본 25분)
              aquarium --card       어항 명함 PNG 생성 (SNS 공유용)
              aquarium --install-hook  현재 git 레포에 커밋 보상 훅 설치
              aquarium --reward     커밋 보상 적립 (git hook이 호출)
              aquarium --achievements  업적 목록 출력
              aquarium --release <이름>  물고기를 분양 코드로 내보내기
              aquarium --adopt <코드>    받은 분양 코드로 물고기 입양
              aquarium --status     저장된 어항 요약 한 줄 출력 (tmux 상태바용)
              aquarium --mailbox    받은편지함 출력
              aquarium --sponsor    후원 링크 출력
              aquarium --version    버전 출력

            키:
              f  먹이 주기          g  생먹이(브라인슈림프)
              p  집중 시작/중단     i  도감
              n  조명 (자동 → 밤 → 낮)
              m  음악 (칩튠 플레이리스트 켜기/끄기)
              q  종료 (자동 저장)   마우스 클릭: 물고기 만지기

            집중이 끝나면 물고기들에게 먹이 대잔치가 열립니다.

            환경변수:
              AQUARIUM_LANG=ko|en                     언어 강제 지정
              AQUARIUM_VISITOR=whale|turtle|octopus   손님이 자주 옵니다 (이스터에그)
            """
            : """
            aquarium — a healing ASCII aquarium in your terminal

            Usage:
              aquarium               run the tank
              aquarium --focus [min] start in pomodoro focus mode (default 25)
              aquarium --card        render a shareable PNG tank card
              aquarium --install-hook  install the commit-reward hook in this repo
              aquarium --reward      bank a commit reward (called by the git hook)
              aquarium --achievements  list all achievements
              aquarium --release <name>  export a fish as a gift code
              aquarium --adopt <code>    adopt a fish from a gift code
              aquarium --status      one-line tank summary (for tmux status bars)
              aquarium --mailbox     print your postcard mailbox
              aquarium --sponsor     print the support link
              aquarium --version     print version

            Keys:
              f  sprinkle food      g  live food (brine shrimp)
              p  start/stop focus   i  tank log
              n  lights (auto → night → day)
              m  music (chiptune playlist on/off)
              q  quit (auto-saves)  mouse click: pet a fish

            When a focus session ends, the fish get a feast.

            Environment:
              AQUARIUM_LANG=ko|en                     force language
              AQUARIUM_VISITOR=whale|turtle|octopus   frequent visitors (easter egg)
            """
    }

    // MARK: - Support (후원)

    static var sponsorTitle: String { t("[ 후원 · Support ☕ ]", "[ Support ☕ ]") }
    static var sponsorThanks1: String {
        t("이 어항은 무료이자 오픈소스예요.", "This little aquarium is free and open source.")
    }
    static var sponsorThanks2: String {
        t("커피 한 잔이 새 물고기와 기능, 밤샘 디버깅의 연료가 됩니다 ☕",
          "A coffee fuels new fish, features, and late-night debugging ☕")
    }
    static var sponsorOpenHint: String {
        t("[o] 브라우저에서 열기   [s] 닫기", "[o] open in browser   [s] close")
    }
    static var sponsorOpened: String {
        t("브라우저에서 후원 페이지를 열었어요. 고마워요! ☕", "Opened the sponsor page — thank you! ☕")
    }
    static var sponsorEnlarge: String { t("후원 안내를 보려면 창을 키워주세요", "Enlarge the window for the support page") }

    // MARK: - Wanderlust & postcards (방랑벽 & 엽서)

    static func departedWander(_ name: String) -> String {
        isKorean ? "\(name)\(subjectParticle(name)) 넓은 바다로 여행을 떠났어요 🌊"
                 : "\(name) set off to explore the open sea 🌊"
    }
    static func postcardArrived(_ name: String, _ location: String) -> String {
        isKorean ? "\(name)\(subjectParticle(name)) \(location)에서 엽서를 보냈어요 🪸"
                 : "\(name) sent a postcard from \(location) 🪸"
    }
    static func postcardsBatch(_ n: Int) -> String {
        t("여행 간 친구들에게서 엽서 \(n)통이 도착했어요 📬", "\(n) postcards arrived from your travelers 📬")
    }
    static func mailboxTitle(_ n: Int) -> String { t("[ 받은편지함 · \(n)통 ]", "[ Mailbox · \(n) ]") }
    static var mailboxEmpty: String {
        t("아직 받은 엽서가 없어요. 여행 간 물고기가 보내줄 거예요.", "No postcards yet — your travelers will write.")
    }
    static var mailboxEnlarge: String { t("받은편지함을 보려면 창을 키워주세요", "Enlarge the window to read mail") }
    static func statusUnread(_ n: Int) -> String { "\u{2709} \(n)" }

    static let postcardLocationCount = 8
    static func postcardLocation(_ i: Int) -> String {
        let ko = ["산호초", "심해", "난파선", "해초 숲", "먼바다", "열대 섬", "따뜻한 해류", "반짝이는 여울"]
        let en = ["the coral reef", "the deep", "a shipwreck", "the kelp forest",
                  "the open sea", "a tropical isle", "a warm current", "a sparkling shoal"]
        let a = isKorean ? ko : en
        return a[min(max(0, i), a.count - 1)]
    }
    static let postcardMessageCount = 8
    static func postcardMessage(_ i: Int) -> String {
        let ko = ["여긴 정말 넓어요!", "새 친구를 잔뜩 사귀었어요", "가끔 어항이 그리워요", "물이 아주 따뜻해요",
                  "오늘 고래를 봤어요!", "모험은 계속돼요", "당신 덕분에 용기가 났어요", "별빛 아래서 헤엄쳐요"]
        let en = ["It's so vast out here!", "Made tons of new friends", "I miss the tank sometimes",
                  "The water is lovely and warm", "Saw a whale today!", "The adventure continues",
                  "You gave me courage", "Swimming under the starlight"]
        let a = isKorean ? ko : en
        return a[min(max(0, i), a.count - 1)]
    }
    static func relativeTime(_ at: Double) -> String {
        let s = max(0, Date().timeIntervalSince1970 - at)
        if s < 90 { return t("방금", "just now") }
        let m = Int(s / 60)
        if m < 60 { return t("\(m)분 전", "\(m)m ago") }
        let h = m / 60
        if h < 24 { return t("\(h)시간 전", "\(h)h ago") }
        return t("\(h / 24)일 전", "\(h / 24)d ago")
    }

    // MARK: - Adoption (분양/입양)

    static func releasedCLI(_ name: String) -> String {
        t("\(name) 분양 준비 완료! 아래 코드를 친구에게 전해주세요 (친구는 aquarium --adopt <코드> 실행):",
          "\(name) is ready to gift! Share this code with a friend (they run: aquarium --adopt <code>):")
    }
    static func releaseNotFound(_ name: String) -> String {
        t("'\(name)' 물고기를 찾을 수 없어요. 도감(i)에서 이름을 확인해주세요.",
          "No fish named '\(name)'. Check names in the log (i).")
    }
    static var releaseFailed: String { t("분양 코드 생성에 실패했어요", "Failed to create the gift code") }
    static func releaseDeparted(_ name: String) -> String {
        isKorean ? "\(name)\(subjectParticle(name)) 새 어항으로 떠났어요 👋" : "\(name) set off for a new tank 👋"
    }
    static var adoptInvalid: String { t("올바른 분양 코드가 아니에요", "That is not a valid gift code") }
    static func adoptQueued(_ name: String) -> String {
        t("\(name) 입양 코드를 받았어요! 어항을 열면 헤엄쳐 들어옵니다.",
          "Got the gift code for \(name)! It will swim in when you open your tank.")
    }
    static func adopted(_ name: String, from: String?) -> String {
        let base = isKorean ? "\(name)\(objectParticle(name)) 입양했어요!" : "You adopted \(name)!"
        guard let from, !from.isEmpty else { return base }
        return isKorean ? base + " (\(from)네 어항 출신)" : base + " (from \(from)'s tank)"
    }
    static func rosterTravelers(_ n: Int) -> String { t("여행 온 물고기   \(n)마리", "Travelers   \(n)") }

    // MARK: - Achievements

    static func achievementUnlocked(_ name: String) -> String {
        t("🏆 업적 달성: \(name)!", "🏆 Achievement unlocked: \(name)!")
    }
    static func achievementsBatch(_ n: Int) -> String {
        t("🏆 그동안의 업적 \(n)개를 획득했어요!", "🏆 Unlocked \(n) achievements so far!")
    }
    static func achievementsHeader(_ have: Int, _ total: Int) -> String {
        t("🏆 업적 \(have)/\(total) 달성", "🏆 Achievements \(have)/\(total)")
    }
    static func rosterAchievements(_ have: Int, _ total: Int) -> String {
        t("업적   \(have)/\(total)  (aquarium --achievements)", "Badges   \(have)/\(total)  (aquarium --achievements)")
    }
    static func cardAchievements(_ have: Int, _ total: Int) -> String {
        t("🏆 업적 \(have)/\(total) 달성", "🏆 \(have)/\(total) achievements")
    }

    // MARK: - Commit rewards

    static func rewardDeposited(_ pending: Int) -> String {
        t("><> 커밋 보상 적립! 어항에 먹이가 도착할 거예요 (대기 \(pending)건)",
          "><> Commit reward banked! Food is on its way to your tank (\(pending) pending)")
    }
    static func rewardArrived(_ commits: Int) -> String {
        t("커밋 보상 도착! 먹이가 쏟아집니다 (커밋 \(commits)건)",
          "Commit reward! Food incoming (\(commits) commits)")
    }
    static func rosterCommits(_ n: Int) -> String { t("커밋 보상   \(n)회", "Commits   \(n) rewarded") }
    static func cardCommits(_ n: Int) -> String {
        t("커밋 \(n)번이 이 물고기들을 키웠어요", "Raised on \(n) commits")
    }
    static func hookInstalled(_ path: String) -> String {
        t("post-commit 훅 설치 완료: \(path)\n이제 커밋할 때마다 물고기 먹이가 적립됩니다!",
          "post-commit hook installed: \(path)\nEvery commit now feeds your fish!")
    }
    static var hookAlreadyInstalled: String { t("이미 설치되어 있어요", "Hook already installed") }
    static var hookNoRepo: String { t("git 저장소가 아니에요 — 레포 안에서 실행해주세요", "Not a git repository — run inside a repo") }

    // MARK: - Card

    static var cardTitle: String { t("나의 터미널 어항", "My Terminal Aquarium") }
    static func cardSwimming(count: Int, days: Int) -> String {
        t("물고기 \(count)마리와 \(days)일째 헤엄치는 중", "Swimming with \(count) fish · day \(days)")
    }
    static func cardFriends(_ names: String) -> String {
        t("\(names) 그리고 친구들", "\(names) & friends")
    }
    static func cardRecords(focus: Int, whale: Int, turtle: Int, octopus: Int) -> String {
        t("집중 \(focus)회 · 고래 \(whale) · 거북이 \(turtle) · 문어 \(octopus)",
          "Focus \(focus) · whale \(whale) · turtle \(turtle) · octopus \(octopus)")
    }
    static func cardSaved(_ path: String) -> String {
        t("어항 명함을 저장했어요: \(path)", "Tank card saved: \(path)")
    }
    static var cardFailed: String { t("명함 저장에 실패했어요", "Failed to save the card") }

    // MARK: - Songs

    static func songTitle(_ index: Int) -> String {
        let titles: [(ko: String, en: String)] = [
            ("물속 산책", "Underwater Stroll"),
            ("달빛 어항", "Moonlit Tank"),
            ("산호초 왈츠", "Coral Reef Waltz"),
            ("새우 행진곡", "Shrimp March"),
            ("심해 탐험", "Deep Sea Dive"),
            ("보물상자 폴카", "Treasure Chest Polka"),
            ("해파리의 꿈", "Jellyfish Dream"),
            ("고래의 노래", "Song of the Whale"),
        ]
        guard index < titles.count else { return "?" }
        return isKorean ? titles[index].ko : titles[index].en
    }
}
