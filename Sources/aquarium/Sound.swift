import Foundation

enum Sound {
    private static var lastPlayed: Double = 0

    /// Short bubbly pop when a fish is touched. Fire-and-forget via afplay.
    static func playTouch() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPlayed > 0.15 else { return }
        lastPlayed = now

        let path = "/System/Library/Sounds/Pop.aiff"
        guard FileManager.default.isReadableFile(atPath: path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = [path]
        try? process.run()
    }

    /// Celebration chime when a focus session completes.
    static func playChime() {
        let path = "/System/Library/Sounds/Glass.aiff"
        guard FileManager.default.isReadableFile(atPath: path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = [path]
        try? process.run()
    }
}
