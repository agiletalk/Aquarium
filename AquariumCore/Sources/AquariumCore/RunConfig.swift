import Foundation

/// resolve 층 — 입력(인자·환경 변수·터미널 응답)을 받아 이번 실행에서 무엇을
/// 보여줄지 확정한다. World는 이 값만 보고 환경을 스스로 읽지 않는다.
public struct RunConfig {
    /// 라운지 전시 모드 — 무인 상설 전시용. 세이브에 남지 않는다.
    public var lounge: Bool
    /// 라운지 타이머 압축(AQUARIUM_LOUNGE_FAST). 테스트용 탈출구.
    public var loungeFast: Bool
    /// 손님 종 고정(AQUARIUM_VISITOR). 테스트용 탈출구.
    public var debugVisitor: String?
    /// OSC 11로 받은 터미널 배경 밝기. nil이면 시스템 다크 모드를 묻는다.
    public var terminalDark: Bool?
    /// 카드 렌더링용 헤드리스 World — 자동 저장·큐 소비·엽서 점검을 건너뛴다.
    public var ephemeral: Bool
    public var storage: Storage
    /// 정원 상한. nil이면 기본 규칙(라운지 120 · 일반 40). 화면 밀도(cols*rows/80)는 그대로 적용된다.
    public var fishCap: Int?
    /// 계절·기념일 판정에 쓸 날짜 고정(AQUARIUM_TODAY=YYYY-MM-DD). 테스트용 탈출구.
    public var debugToday: MonthDay?

    public init(lounge: Bool = false, loungeFast: Bool = false, debugVisitor: String? = nil,
                terminalDark: Bool? = nil, ephemeral: Bool = false, storage: Storage = .terminal,
                fishCap: Int? = nil, debugToday: MonthDay? = nil) {
        self.lounge = lounge
        self.loungeFast = loungeFast
        self.debugVisitor = debugVisitor
        self.terminalDark = terminalDark
        self.ephemeral = ephemeral
        self.storage = storage
        self.fishCap = fishCap
        self.debugToday = debugToday
    }

    /// 터미널 앱의 resolve — 환경 변수에서 테스트용 탈출구를 읽는다.
    public static func terminal(environment env: [String: String], lounge: Bool,
                                terminalDark: Bool?, ephemeral: Bool = false) -> RunConfig {
        RunConfig(lounge: lounge,
                  loungeFast: env["AQUARIUM_LOUNGE_FAST"] != nil,
                  debugVisitor: env["AQUARIUM_VISITOR"],
                  terminalDark: terminalDark,
                  ephemeral: ephemeral,
                  storage: .terminal,
                  debugToday: MonthDay(parsing: env["AQUARIUM_TODAY"]))
    }
}

/// 어항이 읽고 쓰는 파일.
public struct Storage {
    /// 세이브 파일. nil이면 저장하지 않는다.
    public var saveURL: URL?
    /// 터미널 CLI의 큐(커밋 보상·입양·분양)를 소비할지. 같은 큐를 두 어항이
    /// 소비하면 먼저 읽은 쪽이 가져가므로, 터미널 어항만 켠다.
    public var pollsTerminalQueues: Bool

    public init(saveURL: URL?, pollsTerminalQueues: Bool) {
        self.saveURL = saveURL
        self.pollsTerminalQueues = pollsTerminalQueues
    }

    /// 터미널 어항 — `~/.aquarium.json` + 큐 소비.
    public static var terminal: Storage {
        Storage(saveURL: SaveStore.fileURL, pollsTerminalQueues: true)
    }
}

/// 달력의 월·일 — 계절과 기념일 판정 입력.
public struct MonthDay: Equatable {
    public var month: Int
    public var day: Int

    public init(month: Int, day: Int) {
        self.month = month
        self.day = day
    }

    /// "YYYY-MM-DD" → 월·일. 형식이 틀리면 nil(조용히 실제 날짜를 쓴다).
    public init?(parsing text: String?) {
        guard let parts = text?.split(separator: "-"), parts.count == 3,
              let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(month: month, day: day)
    }
}

/// 시각을 받아 연출을 판정하는 순수 함수. 실행 중에도 바뀌는 값이라
/// RunConfig에 고정하지 않고 World가 주기적으로 부른다.
public enum Resolve {
    /// 여름 판정 — auto면 달력 기준 6–8월.
    public static func isSummer(season: Season, month: Int) -> Bool {
        switch season {
        case .summer: return true
        case .off, .autumn: return false
        case .auto: return (6...8).contains(month)
        }
    }

    /// 가을 판정 — auto면 달력 기준 9–11월.
    public static func isAutumn(season: Season, month: Int) -> Bool {
        switch season {
        case .autumn: return true
        case .off, .summer: return false
        case .auto: return (9...11).contains(month)
        }
    }

    /// 할로윈 — 가을 연출이 켜진 10월 31일. 계절을 끄거나 여름으로 고정하면 오지 않는다.
    public static func isHalloween(season: Season, today: MonthDay) -> Bool {
        isAutumn(season: season, month: today.month) && today.month == 10 && today.day == 31
    }

    /// auto 조명의 밤 판정 — 19시~7시이거나 배경이 어두우면 밤.
    public static func isEnvNight(hour: Int, dark: Bool) -> Bool {
        let nightHours = hour >= 19 || hour < 7
        return dark || nightHours
    }
}
