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

    // MARK: - Status bar

    static func statusFish(_ n: Int) -> String { t("물고기 \(n)마리", "\(n) fish") }
    static func statusFood(_ n: Int) -> String { t("먹이 \(n)", "food \(n)") }
    static func statusDay(_ days: Int, _ time: String) -> String { t("\(days)일째 \(time)", "day \(days) · \(time)") }
    static func modeLabel(auto: Bool, night: Bool) -> String {
        if auto { return t(night ? "밤·자동" : "낮·자동", night ? "night·auto" : "day·auto") }
        return t(night ? "밤" : "낮", night ? "night" : "day")
    }
    static var helpLine: String {
        t("[f] 먹이  [g] 생먹이  [i] 도감  [n] 조명  [m] 음악  [q] 종료",
          "[f] feed  [g] live food  [i] log  [n] lights  [m] music  [q] quit")
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
              aquarium             어항 실행
              aquarium --status    저장된 어항 요약 한 줄 출력 (tmux 상태바용)
              aquarium --version   버전 출력

            키:
              f  먹이 주기          g  생먹이(브라인슈림프)
              i  도감               n  조명 (자동 → 밤 → 낮)
              m  음악 (칩튠 플레이리스트 켜기/끄기)
              q  종료 (자동 저장)   마우스 클릭: 물고기 만지기

            환경변수:
              AQUARIUM_LANG=ko|en                     언어 강제 지정
              AQUARIUM_VISITOR=whale|turtle|octopus   손님이 자주 옵니다 (이스터에그)
            """
            : """
            aquarium — a healing ASCII aquarium in your terminal

            Usage:
              aquarium             run the tank
              aquarium --status    one-line tank summary (for tmux status bars)
              aquarium --version   print version

            Keys:
              f  sprinkle food      g  live food (brine shrimp)
              i  tank log           n  lights (auto → night → day)
              m  music (chiptune playlist on/off)
              q  quit (auto-saves)  mouse click: pet a fish

            Environment:
              AQUARIUM_LANG=ko|en                     force language
              AQUARIUM_VISITOR=whale|turtle|octopus   frequent visitors (easter egg)
            """
    }

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
