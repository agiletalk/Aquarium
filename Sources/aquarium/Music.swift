import AVFoundation
import Foundation

struct ChipSong {
    let title: String
    let stepDuration: Double // seconds per 8th-note step
    let loops: Int
    let melody: [Int] // MIDI note numbers, 0 = rest
    let bass: [Int]
}

/// DOS 시절 감성의 칩튠 신시사이저.
/// 외부 파일 없이 사각파(멜로디) + 삼각파(베이스)를 실시간 합성한다.
final class MusicPlayer {
    static let shared = MusicPlayer()

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private(set) var isPlaying = false
    private var lastAnnounced = -1

    // Audio-thread state (render block에서만 변경)
    private var clock: Double = 0
    private var songIndex = 0
    private var melodyPhase: Double = 0
    private var bassPhase: Double = 0
    private let sampleRate: Double = 44100

    private let songs: [ChipSong] = [
        ChipSong(title: "물속 산책", stepDuration: 0.22, loops: 2,
                 melody: [72, 0, 74, 0, 76, 0, 79, 76,
                          74, 72, 0, 69, 0, 72, 0, 0,
                          76, 0, 79, 0, 81, 79, 76, 74,
                          72, 0, 74, 72, 69, 0, 67, 0],
                 bass: [48, 0, 55, 0, 48, 0, 55, 0,
                        45, 0, 52, 0, 45, 0, 52, 0,
                        41, 0, 48, 0, 41, 0, 48, 0,
                        43, 0, 50, 0, 43, 0, 50, 0]),
        ChipSong(title: "달빛 어항", stepDuration: 0.3, loops: 2,
                 melody: [69, 0, 0, 72, 0, 0, 76, 0,
                          74, 0, 72, 0, 69, 0, 0, 0,
                          67, 0, 69, 0, 72, 0, 76, 0,
                          74, 0, 72, 0, 69, 0, 0, 0],
                 bass: [45, 0, 0, 0, 52, 0, 0, 0,
                        41, 0, 0, 0, 48, 0, 0, 0,
                        48, 0, 0, 0, 55, 0, 0, 0,
                        43, 0, 0, 0, 50, 0, 0, 0]),
        ChipSong(title: "산호초 왈츠", stepDuration: 0.25, loops: 2,
                 melody: [77, 0, 79, 81, 0, 79,
                          77, 0, 74, 76, 0, 72,
                          74, 0, 76, 77, 0, 79,
                          81, 0, 79, 77, 0, 74,
                          72, 0, 74, 76, 0, 77,
                          77, 0, 0, 0, 0, 0],
                 bass: [41, 0, 0, 53, 0, 0,
                        46, 0, 0, 58, 0, 0,
                        48, 0, 0, 55, 0, 0,
                        41, 0, 0, 53, 0, 0,
                        46, 0, 0, 48, 0, 0,
                        41, 0, 0, 0, 0, 0]),
        ChipSong(title: "새우 행진곡", stepDuration: 0.16, loops: 3,
                 melody: [79, 79, 0, 81, 79, 0, 76, 0,
                          74, 76, 79, 0, 81, 0, 83, 0,
                          79, 0, 76, 74, 0, 71, 0, 74,
                          79, 0, 81, 83, 86, 83, 79, 0],
                 bass: [43, 0, 50, 0, 43, 0, 50, 0,
                        40, 0, 47, 0, 40, 0, 47, 0,
                        36, 0, 43, 0, 36, 0, 43, 0,
                        38, 0, 45, 0, 38, 0, 45, 0]),
        ChipSong(title: "심해 탐험", stepDuration: 0.28, loops: 2,
                 melody: [74, 0, 72, 70, 0, 69, 0, 67,
                          65, 0, 67, 69, 0, 0, 0, 0,
                          69, 0, 72, 0, 74, 72, 69, 67,
                          65, 0, 64, 0, 62, 0, 0, 0],
                 bass: [38, 0, 45, 0, 38, 0, 45, 0,
                        46, 0, 53, 0, 46, 0, 53, 0,
                        41, 0, 48, 0, 41, 0, 48, 0,
                        36, 0, 43, 0, 36, 0, 43, 0]),
        ChipSong(title: "보물상자 폴카", stepDuration: 0.18, loops: 3,
                 melody: [74, 0, 78, 0, 81, 0, 78, 74,
                          79, 0, 83, 79, 76, 0, 79, 0,
                          81, 0, 73, 0, 76, 0, 73, 0,
                          74, 76, 78, 76, 74, 0, 74, 0],
                 bass: [38, 45, 38, 45, 38, 45, 38, 45,
                        43, 50, 43, 50, 43, 50, 43, 50,
                        45, 52, 45, 52, 45, 52, 45, 52,
                        38, 45, 38, 45, 38, 45, 38, 45]),
        ChipSong(title: "해파리의 꿈", stepDuration: 0.34, loops: 2,
                 melody: [76, 0, 0, 79, 0, 0, 83, 0,
                          81, 0, 79, 0, 76, 0, 0, 0,
                          74, 0, 76, 0, 79, 0, 74, 0,
                          71, 0, 74, 0, 76, 0, 0, 0],
                 bass: [40, 0, 0, 0, 47, 0, 0, 0,
                        36, 0, 0, 0, 43, 0, 0, 0,
                        43, 0, 0, 0, 50, 0, 0, 0,
                        38, 0, 0, 0, 45, 0, 0, 0]),
        ChipSong(title: "고래의 노래", stepDuration: 0.32, loops: 2,
                 melody: [72, 0, 0, 79, 0, 0, 76, 0,
                          69, 0, 0, 76, 0, 0, 72, 0,
                          77, 0, 0, 81, 0, 0, 84, 0,
                          79, 0, 77, 76, 74, 0, 0, 0],
                 bass: [36, 0, 43, 0, 48, 0, 43, 0,
                        45, 0, 52, 0, 57, 0, 52, 0,
                        41, 0, 48, 0, 53, 0, 48, 0,
                        43, 0, 50, 0, 55, 0, 50, 0]),
    ]

    /// Returns the status message to show in the tank.
    func toggle() -> String {
        if isPlaying {
            engine.stop()
            isPlaying = false
            return L10n.musicOff
        }
        setupIfNeeded()
        do {
            engine.prepare()
            try engine.start()
            isPlaying = true
            lastAnnounced = -1
            return L10n.musicOn
        } catch {
            return L10n.musicFailed
        }
    }

    /// Song changed since last poll? Used for "지금 나오는 곡" announcements.
    func pollNewTitle() -> String? {
        guard isPlaying, lastAnnounced != songIndex else { return nil }
        lastAnnounced = songIndex
        return L10n.songTitle(songIndex)
    }

    private func setupIfNeeded() {
        guard source == nil else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        let node = AVAudioSourceNode { [unowned self] _, _, frameCount, audioBufferList in
            self.render(frameCount: frameCount, audioBufferList: audioBufferList)
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.6
        source = node
    }

    private func render(frameCount: AVAudioFrameCount,
                        audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }

        let song = songs[songIndex]
        let steps = song.melody.count
        let songLength = Double(steps) * song.stepDuration * Double(song.loops)

        for frame in 0..<Int(frameCount) {
            let t = clock + Double(frame) / sampleRate
            let stepFloat = t / song.stepDuration
            let step = Int(stepFloat) % steps
            let stepPhase = stepFloat - stepFloat.rounded(.down)

            var sample = 0.0

            let melodyNote = song.melody[step]
            if melodyNote > 0 {
                let vibrato = 1 + 0.004 * sin(2 * .pi * 5 * t)
                let freq = 440 * pow(2, (Double(melodyNote) - 69) / 12) * vibrato
                melodyPhase += freq / sampleRate
                let pulse: Double = melodyPhase.truncatingRemainder(dividingBy: 1) < 0.25 ? 1 : -1
                sample += pulse * pow(max(0, 1 - stepPhase), 1.6) * 0.05 // plucky decay
            }

            let bassNote = song.bass[step % song.bass.count]
            if bassNote > 0 {
                let freq = 440 * pow(2, (Double(bassNote) - 69) / 12)
                bassPhase += freq / sampleRate
                let p = bassPhase.truncatingRemainder(dividingBy: 1)
                sample += (4 * abs(p - 0.5) - 1) * max(0, 1 - stepPhase * 0.8) * 0.06
            }

            out[frame] = Float(sample)
        }

        clock += Double(frameCount) / sampleRate
        if clock >= songLength {
            clock = 0
            melodyPhase = 0
            bassPhase = 0
            songIndex = (songIndex + 1) % songs.count
        }
        return noErr
    }
}
