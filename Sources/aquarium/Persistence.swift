import Foundation

struct FishState: Codable {
    var species: Int
    var color: UInt8
    var speed: Double
    var eaten: Int
    var growRemaining: Double? // nil = adult
}

struct SaveState: Codable {
    var version: Int = 1
    var savedAt: Double      // wall-clock epoch, for offline-time calculation
    var tankBornAt: Double   // wall-clock epoch
    var breedRemaining: Double
    var lighting: String
    var fish: [FishState]
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
