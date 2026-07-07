import Foundation

struct FishState: Codable {
    var species: Int
    var color: UInt8
    var speed: Double
    var eaten: Int
    var growRemaining: Double? // nil = adult
    var name: String?          // optional: v1.2 saves have no names
    var bornAt: Double?        // wall-clock epoch
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
