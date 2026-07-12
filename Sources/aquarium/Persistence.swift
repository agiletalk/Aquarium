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

    static func deposit() -> Int {
        let next = pending() + 1
        try? "\(next)".write(to: fileURL, atomically: true, encoding: .utf8)
        return next
    }

    static func pending() -> Int {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return 0 }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func consume() -> Int {
        let count = pending()
        if count > 0 { try? "0".write(to: fileURL, atomically: true, encoding: .utf8) }
        return count
    }
}

/// 입양 인박스: `aquarium --adopt <코드>`가 넣고, 실행 중인 앱이 물고기로 되살린다.
enum AdoptInbox {
    static var fileURL: URL {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".aquarium-adopt-inbox")
    }

    static func deposit(_ token: String) {
        var lines = drainPeek()
        lines.append(token)
        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func drainPeek() -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    static func drain() -> [String] {
        let lines = drainPeek()
        if !lines.isEmpty { try? FileManager.default.removeItem(at: fileURL) }
        return lines
    }
}

/// 분양 아웃박스: `aquarium --release <이름>`이 떠나보낼 물고기 이름을 넣고, 앱이 어항에서 제거한다.
enum ReleaseOutbox {
    static var fileURL: URL {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".aquarium-release-outbox")
    }

    static func request(_ name: String) {
        var lines = peek()
        lines.append(name)
        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func peek() -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    static func drain() -> [String] {
        let lines = peek()
        if !lines.isEmpty { try? FileManager.default.removeItem(at: fileURL) }
        return lines
    }
}
