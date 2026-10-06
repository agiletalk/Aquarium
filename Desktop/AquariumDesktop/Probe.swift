import Foundation

/// 렌더링 개발 도구 — AQUARIUM_PROBE=<파일>일 때만 켜진다(꺼져 있으면 비용 없음).
/// - 10초마다 단계별 µs/frame·CPU%를 파일에 쓴다.
/// - 100프레임마다 앞 버퍼를 처음부터 다시 그린 결과와 픽셀 단위로 비교한다(부분 갱신 잔상 검출).
///   AQUARIUM_PROBE_NOVERIFY=1이면 비교를 끈다 — 비교 자체가 비싸 CPU 측정을 부풀린다.
/// - 켜져 있으면 가려져도 계속 그린다(렌더 비용은 보이든 말든 같다).
enum Probe {
    static let path = ProcessInfo.processInfo.environment["AQUARIUM_PROBE"]
    static var enabled: Bool { path != nil }
    static let noVerify = ProcessInfo.processInfo.environment["AQUARIUM_PROBE_NOVERIFY"] != nil
    struct CellKey: Hashable { let row: Int; let col: Int }
    static var bigCells: Set<CellKey> = []
    static var cellPixelWidth = 0.0
    static var cellPixelHeight = 0
    private static var verifyCount = 0
    private static var verifyBad = 0
    private static var verifyRuns = 0

    /// 100프레임마다 앞 버퍼를 처음부터 다시 그린 결과와 비교한다.
    static func verifyTick(_ check: () -> (mismatched: Int, total: Int)) {
        guard !noVerify else { return }
        verifyCount += 1
        guard verifyCount % 100 == 0 else { return }
        let r = check()
        verifyRuns += 1
        verifyBad += r.mismatched > 0 ? 1 : 0
        log(String(format: "verify #%d: %d / %d px 불일치", verifyRuns, r.mismatched, r.total))
    }

    static func log(_ line: String) {
        guard let path else { return }
        let out = line + "\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(out.data(using: .utf8)!); h.closeFile() }
        else { FileManager.default.createFile(atPath: path, contents: out.data(using: .utf8)) }
    }
    private static var totals: [String: UInt64] = [:]
    private static var counts: [String: Int] = [:]
    private static var frames = 0
    private static var started: UInt64 = 0

    @inline(__always) static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    static func add(_ name: String, since start: UInt64, count: Int = 0) {
        guard enabled else { return }
        totals[name, default: 0] += now() - start
        counts[name, default: 0] += count
    }

    static func frame() {
        guard let path else { return }
        frames += 1
        let t = now()
        if started == 0 { started = t; return }
        let elapsed = t - started
        guard elapsed > 10_000_000_000 else { return }
        var out = String(format: "--- %.1fs, %d frames (%.1f fps)\n", Double(elapsed) / 1e9, frames,
                         Double(frames) / (Double(elapsed) / 1e9))
        for (k, v) in totals.sorted(by: { $0.value > $1.value }) {
            let perFrame = Double(v) / Double(frames) / 1000
            let cpu = Double(v) / Double(elapsed) * 100
            let n = counts[k].map { $0 > 0 ? String(format: "  avg n=%.0f", Double($0) / Double(frames)) : "" } ?? ""
            out += String(format: "%-14@ %8.1f µs/frame  %5.2f%% CPU%@\n", k as NSString, perFrame, cpu, n as NSString)
        }
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(out.data(using: .utf8)!); h.closeFile() }
        else { FileManager.default.createFile(atPath: path, contents: out.data(using: .utf8)) }
        totals = [:]; counts = [:]; frames = 0; started = now()
    }
}
