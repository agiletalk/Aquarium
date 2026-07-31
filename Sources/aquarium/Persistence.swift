import Foundation

struct FishState: Codable {
    var species: Int
    var color: UInt8
    var speed: Double
    var eaten: Int
    var growRemaining: Double? // nil = adult
    var name: String?          // optional: v1.2 saves have no names
    var bornAt: Double?        // wall-clock epoch
    var id: String?            // 분양용 고유 id
    var origin: [String]?      // 거쳐온 어항들 (여권)
    var morph: Int?            // 희귀 변종 (nil/0 = normal)
    var personality: Int?      // 영구 기질 (nil = 구 세이브 → 로드 시 랜덤 배정)
}

struct SaveState: Codable {
    var version: Int = 1
    var savedAt: Double      // wall-clock epoch, for offline-time calculation
    var tankBornAt: Double   // wall-clock epoch
    var breedRemaining: Double
    var lighting: String
    var fish: [FishState]
    var visitorSeen: [String: Int]? // 도감 손님 기록
    var focusDone: Int?             // 완료한 뽀모도로 세션 수
    var tankFull: Bool?             // 저장 시점에 정원이 찼는지 (--status 표시용)
    var commitRewards: Int?         // 커밋 보상 누적 횟수
    var stats: [String: Int]?       // 업적 판정용 카운터
    var unlockedAchievements: [String]? // 획득한 업적 id
    var travelers: [Traveler]?      // 여행 떠난 물고기들 (엽서를 보냄)
    var mailbox: [Postcard]?        // 받은 엽서
    var season: String?             // 계절 테마 (nil = 구 세이브 → auto)
}

struct Traveler: Codable {
    var name: String
    var departedAt: Double      // epoch
    var nextPostcardAt: Double  // epoch
    var sent: Int
}

struct Postcard: Codable {
    var from: String
    var location: Int   // L10n 풀 인덱스 (언어 전환 대응)
    var message: Int
    var at: Double      // 받은 시각 epoch
    var read: Bool
}

/// flock(2) 기반 프로세스 간 배타 락.
///
/// 락 대상은 데이터 파일이 아니라 옆에 둔 `.lock` 사이드카다. 이게 요점이다 —
/// 적재는 write(atomically:)로 rename하고 소비는 removeItem으로 unlink한다.
/// 둘 다 inode를 갈아치우기 때문에 데이터 파일을 직접 잠그면 상대는 이미
/// 떨어져 나간 inode를 잠그게 되고, 락은 조용히 무력화된다. 테스트에서는
/// "동작하는 것처럼" 보인다.
///
/// 전부 LOCK_NB다. 어항은 12.5fps 렌더 루프 안에서 큐를 훑는데 여기서
/// 블로킹되면 화면이 그대로 멈춘다. 못 잡으면 실패하고 다음 점검에서 다시
/// 온다 — 데이터는 파일에 남아 있으니 잃는 게 없다.
enum FileLock {
    /// - Parameter retries: 50ms 간격 재시도 횟수. 잠깐 기다려도 되는
    ///   CLI만 쓴다(어항은 0).
    /// - Returns: 락을 못 잡으면 nil. `body`가 아예 실행되지 않았다는 뜻이다.
    static func withLock<T>(_ url: URL, retries: Int = 0, _ body: () -> T) -> T? {
        let fd = open(url.path + ".lock", O_RDWR | O_CREAT, 0o644)
        // 락 파일조차 못 열면(읽기 전용 HOME 등) 락 없이 진행한다 — 지금까지의
        // 동작 그대로다. 락을 못 만든다고 선물을 버릴 이유는 없다.
        guard fd >= 0 else { return body() }
        defer { close(fd) }

        var attempt = 0
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard attempt < retries else { return nil }
            attempt += 1
            usleep(50_000)
        }
        defer { flock(fd, LOCK_UN) }
        return body()
    }
}

enum SaveStore {
    static var fileURL: URL {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".aquarium.json")
    }

    static func load() -> SaveState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SaveState.self, from: data)
    }

    static func write(_ state: SaveState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// git post-commit 훅이 적립하는 보상 인박스.
/// 실행 중인 앱과의 저장 파일 쓰기 충돌을 피하려고 별도 파일을 쓴다.
enum RewardInbox {
    static var fileURL: URL {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".aquarium-inbox")
    }

    /// 커밋 훅이 부른다. 락을 끝내 못 잡으면 락 없이 진행한다 — 호출자가
    /// 실패로 할 수 있는 일이 없고(훅은 커밋을 되돌리지 않는다), 유실돼도
    /// 먹이 몇 알이다. 선물과 달리 되돌릴 수 없는 손실이 아니다.
    static func deposit() -> Int {
        FileLock.withLock(fileURL, retries: 10, depositLocked) ?? depositLocked()
    }

    private static func depositLocked() -> Int {
        let next = pending() + 1
        try? "\(next)".write(to: fileURL, atomically: true, encoding: .utf8)
        return next
    }

    static func pending() -> Int {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return 0 }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func consume() -> Int {
        // 어항 쪽 — 못 잡으면 이번 점검은 건너뛴다. 숫자는 파일에 남아 있다.
        FileLock.withLock(fileURL) {
            let count = pending()
            if count > 0 { try? "0".write(to: fileURL, atomically: true, encoding: .utf8) }
            return count
        } ?? 0
    }
}

/// 입양 인박스: `aquarium --adopt <코드>`가 넣고, 실행 중인 앱이 물고기로 되살린다.
enum AdoptInbox {
    static var fileURL: URL {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".aquarium-adopt-inbox")
    }

    /// - Returns: 큐에 실제로 적재됐는지. 호출자(`Passport.adopt`)가 이걸로
    ///   종료 코드를 가른다 — poller가 유실된 코드에 🐠를 붙이면 안 된다.
    /// - Returns: 큐에 실제로 적재됐는지. 호출자(`Passport.adopt`)가 이걸로
    ///   종료 코드를 가른다 — poller가 유실된 코드에 🐠를 붙이면 안 된다.
    ///
    /// 여기만 락 실패를 실패로 보고한다(Reward/Release는 락 없이 강행한다).
    /// 선물은 되돌릴 수 없는 손실이고, 호출자가 exit 75로 재시도를 시킬 수
    /// 있기 때문이다 — 알릴 수 있는 곳에서는 알리고, 아무도 손쓸 수 없는
    /// 곳에서만 조용히 물러난다.
    @discardableResult
    static func deposit(_ token: String) -> Bool {
        FileLock.withLock(fileURL, retries: 10) {
            var lines = drainPeek()
            lines.append(token)
            do {
                try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
                return true
            } catch {
                return false
            }
        } ?? false
    }

    private static func drainPeek() -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    static func drain() -> [String] {
        // 어항 쪽 — 못 잡으면 이번 점검은 건너뛴다. 토큰은 파일에 남아 있다.
        FileLock.withLock(fileURL) {
            let lines = drainPeek()
            if !lines.isEmpty { try? FileManager.default.removeItem(at: fileURL) }
            return lines
        } ?? []
    }
}

/// 분양 아웃박스: `aquarium --release <이름>`이 떠나보낼 물고기 이름을 넣고, 앱이 어항에서 제거한다.
enum ReleaseOutbox {
    static var fileURL: URL {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".aquarium-release-outbox")
    }

    /// 락을 끝내 못 잡으면 락 없이 강행한다 — 호출자(`--release`)가 이미
    /// 코드를 출력하기 직전이라 실패로 할 수 있는 일이 없다.
    static func request(_ name: String) {
        let write = {
            var lines = peek()
            lines.append(name)
            try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        }
        if FileLock.withLock(fileURL, retries: 10, write) == nil { write() }
    }

    private static func peek() -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    static func drain() -> [String] {
        // 어항 쪽 — 못 잡으면 이번 점검은 건너뛴다. 이름은 파일에 남아 있다.
        FileLock.withLock(fileURL) {
            let lines = peek()
            if !lines.isEmpty { try? FileManager.default.removeItem(at: fileURL) }
            return lines
        } ?? []
    }
}
