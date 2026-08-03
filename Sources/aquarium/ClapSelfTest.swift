import Foundation

/// `AQUARIUM_CLAP_SELFTEST=1 aquarium` — ClapDetector 픽스처.
///
/// 이 레포엔 테스트 타깃도 Tests/ 디렉토리도 없다. 그래서 픽스처를 바이너리
/// 안에 두고 env로 연다. AQUARIUM_LOUNGE_FAST·AQUARIUM_VISITOR와 같은 성격의
/// 탈출구라 --help·README에는 싣지 않는다.
///
/// 판정기가 (rms, dt) 순수 함수라서 마이크도 오디오 장치도 필요 없다.
enum ClapSelfTest {

    /// ClapListener의 분석 홉과 같아야 한다 — 픽스처와 실제 동작이 같은 격자를 쓴다.
    static let hop = 512.0 / 48_000.0   // ≈ 10.667 ms

    // MARK: - 신호 빌더

    struct Signal {
        private(set) var samples: [(rms: Float, dt: Double)] = []
        private(set) var elapsed: Double = 0
        /// 방 배경 소음. 기본값은 실측 사무실 mean.
        var bed: Float = 0.00269

        mutating func append(_ rms: Float, _ dt: Double) {
            samples.append((rms, dt))
            elapsed += dt
        }

        mutating func level(_ rms: Float, _ seconds: Double) {
            var remaining = seconds
            while remaining > 1e-9 {
                let dt = min(hop, remaining)
                append(rms, dt)
                remaining -= dt
            }
        }

        mutating func quiet(_ seconds: Double) { level(bed, seconds) }

        mutating func quietUntil(_ target: Double) {
            levelUntil(bed, target)
        }

        /// 지정 시각까지 일정 레벨을 유지한다. quietUntil과 달리 bed로 떨어지지
        /// 않는다 — 꼬리를 릴리스 문턱 위에 붙잡아 두는 픽스처에 필요하다.
        mutating func levelUntil(_ rms: Float, _ target: Double) {
            while elapsed < target - 1e-9 {
                append(rms, min(hop, target - elapsed))
            }
        }

        /// 결정론적 흔들림이 있는 지속음(박수갈채·환호). 난수를 쓰지 않는다 —
        /// 셀프테스트는 재현 가능해야 한다.
        mutating func sustained(_ rms: Float, _ seconds: Double, wobbleHz: Double = 3) {
            var t = 0.0
            while t < seconds {
                append(rms * Float(1 + 0.2 * sin(2 * .pi * wobbleHz * t)), hop)
                t += hop
            }
        }

        /// 트랜지언트 한 발. 2홉이 확실히 임계 위에 있고, rt60 > 0이면 잔향 꼬리.
        ///
        /// 꼬리는 단조 감쇠가 아니라 4Hz로 ±50% 출렁인다. 실제 잔향은 모드
        /// 간섭으로 출렁이고, **그 출렁임이 히스테리시스가 없을 때 가짜 두 번째
        /// 온셋을 만드는 진짜 메커니즘**이다. 단조 꼬리로 만들면 이 픽스처는
        /// 아무것도 못 잡는다.
        mutating func transient(peak: Float, rt60: Double = 0) {
            append(peak, hop)
            append(peak * 0.5, hop)
            guard rt60 > 0 else { return }
            let perHop = Float(pow(10.0, -3.0 * hop / rt60))   // -60 dB / rt60
            var envelope = peak * 0.5 * perHop
            var t = 0.0
            while envelope > bed, t < rt60 * 2 {
                append(max(envelope * Float(1 + 0.5 * sin(2 * .pi * 4 * t)), bed), hop)
                envelope *= perHop
                t += hop
            }
        }

        /// 두 번째 온셋 홉이 첫 번째로부터 **정확히 gap초** 뒤에 놓이게 한다.
        /// sinceOnset은 "첫 온셋 이후 dt 합 + 둘째 온셋 홉의 dt"이므로 둘째 홉의
        /// 시작 시각을 t0+gap에 맞추면 sinceOnset == gap이 된다. 부동소수 오차는
        /// ~1e-15, 경계 마진은 1e-3이라 299/301/599/601 검증에 안전하다.
        mutating func pair(gap: Double, peak: Float = 0.4, rt60: Double = 0) {
            let t0 = elapsed
            transient(peak: peak, rt60: rt60)
            quietUntil(t0 + gap)
            transient(peak: peak, rt60: rt60)
        }
    }

    // MARK: - 케이스

    struct Case {
        let name: String
        let signal: Signal
        let expectedTriggers: Int
        /// 트리거 수만으로는 못 잡는 것들(온셋 개수·바닥 위치)을 검사한다.
        var extra: ((ClapDetector) -> String?)?

        init(_ name: String, _ signal: Signal, triggers: Int,
             extra: ((ClapDetector) -> String?)? = nil) {
            self.name = name
            self.signal = signal
            self.expectedTriggers = triggers
            self.extra = extra
        }
    }

    static func cases() -> [Case] {
        var all: [Case] = []

        // 0. 실측 사무실 배경 소음 재현 (2026-08-03, 562홉)
        //    mean 0.00269 / p95 0.00467 / MAX 0.01272 → 온셋 0이어야 한다.
        //    onsetAbsMin을 0.0127 아래로 내리면 이 케이스가 빨개진다.
        do {
            var s = Signal()
            var i = 0
            while s.elapsed < 6.0 {
                // 결정론적 분포 근사: 대부분 mean, 5%는 p95, 드물게 MAX.
                let v: Float = i % 97 == 0 ? 0.01272 : (i % 20 == 0 ? 0.00467 : 0.00269)
                s.append(v, hop)
                i += 1
            }
            all.append(Case("실측 사무실 정적 6초 (MAX 0.01272)", s, triggers: 0) {
                $0.onsetCount == 0 ? nil : "온셋 0을 기대했으나 \($0.onsetCount)"
            })
        }

        // 1. 조용한 방 + 아주 작은 소리 두 번 (450ms)
        //    0.012는 의도적으로 floor*6(0.0015*6=0.009)보다 크고 onsetAbsMin
        //    (0.018)보다 작게 골랐다. 절대하한을 지우면 여기가 빨개진다 —
        //    그게 이 픽스처의 존재 이유(원 스케치의 1번 버그)다. 이 숫자를
        //    "정리"하지 말 것.
        do {
            var s = Signal(); s.bed = 0.0008
            s.quiet(3.0)
            s.pair(gap: 0.45, peak: 0.012)
            s.quiet(1.0)
            all.append(Case("조용한 방 + 미세한 소리 2회 450ms", s, triggers: 0) {
                $0.onsetCount == 0 ? nil : "온셋 0을 기대했으나 \($0.onsetCount)"
            })
        }

        // 2. 지속 박수갈채 6초 — 바닥이 걸어 올라가면 안 되고, 온셋은 상승
        //    에지 하나뿐이어야 한다.
        //
        //    ⚠️ 뒤에 정적을 붙이면 안 된다. floorTauDown이 0.5초라 2초만 조용해도
        //    바닥이 회복해버려서, 갈채 중에 걸어 올라간 걸 끝 시점 검사로는 못
        //    잡는다. 처음엔 그렇게 썼다가 변이 테스트(동결 제거 → 여전히 통과)로
        //    발각됐다. 신호를 갈채가 끝나는 지점에서 끊어야 d.floor가 갈채 구간을
        //    반영한다.
        do {
            var s = Signal()
            s.quiet(2.0); s.sustained(0.15, 6.0)
            all.append(Case("지속 박수갈채 6초 (바닥 동결)", s, triggers: 0) { d in
                if d.onsetCount != 1 { return "상승 에지 1개를 기대했으나 \(d.onsetCount)" }
                if d.floor >= 0.006 { return "바닥이 \(d.floor)까지 걸어 올라갔다" }
                return nil
            })
        }

        // 3. 기립박수 12초 → 2초 뒤 더블 클랩이 여전히 먹혀야 한다.
        //    8초에 동결이 풀려 바닥이 오르고, floorTauDown(0.5s)로 2초 만에
        //    회복하는 경로 전체를 검증한다.
        do {
            var s = Signal()
            s.quiet(2.0); s.sustained(0.15, 12.0); s.quiet(2.0)
            s.pair(gap: 0.45); s.quiet(1.0)
            all.append(Case("기립박수 12초 → 2초 뒤 더블 클랩", s, triggers: 1))
        }

        // 4. 단발 박수 (건조한 방)
        do {
            var s = Signal()
            s.quiet(2.0); s.transient(peak: 0.4); s.quiet(2.0)
            all.append(Case("단발 박수", s, triggers: 0) {
                $0.onsetCount == 1 ? nil : "온셋 1을 기대했으나 \($0.onsetCount)"
            })
        }

        // 5. 단발 박수 + 잔향 꼬리 (출렁이는 감쇠)
        do {
            var s = Signal()
            s.quiet(2.0); s.transient(peak: 0.4, rt60: 1.0); s.quiet(2.0)
            all.append(Case("단발 박수 + 잔향 꼬리 RT60 1.0s", s, triggers: 0) {
                $0.onsetCount == 1 ? nil : "꼬리가 \($0.onsetCount)개 온셋으로 쪼개졌다"
            })
        }

        // 5b. 단발 박수 + 400ms 뒤 벽 반사 — **히스테리시스의 진짜 시험대.**
        //
        //     딱딱한 라운지에서 물리적으로 일어나는 일이다: 직접음 뒤에 먼 벽에서
        //     되돌아온 1차 반사가 뚜렷한 두 번째 트랜지언트로 도착한다. 그게
        //     하필 짝 판정 창(300~600ms) 안이면 박수 한 번이 더블 클랩이 된다.
        //
        //     숫자를 히스테리시스에 정확히 걸리게 골랐다. 사이 꼬리는 0.012 —
        //     releaseLevel(0.018 × 0.4 = 0.0072)보다 높아 hot이 유지되므로 반사가
        //     새 온셋을 못 만든다. releaseFactor를 1.0으로 올리면 releaseLevel이
        //     0.018이 되어 꼬리 0.012에서 릴리스되고, 반사 0.05가 두 번째 온셋이
        //     되어 400ms 짝이 성립한다 → 오탐.
        //
        //     5번(출렁이는 꼬리)만으로는 이걸 못 잡았다. 변이 테스트에서
        //     releaseFactor 1.0에도 통과해버려서 이 케이스를 새로 넣었다.
        do {
            var s = Signal()
            s.quiet(2.0)
            let t0 = s.elapsed
            s.transient(peak: 0.4)
            // 꼬리를 반사음 직전까지 0.012로 유지한다. bed로 떨어지면 releaseLevel
            // 아래라 릴리스돼서, 히스테리시스가 아니라 꼬리 모양을 시험하게 된다.
            s.levelUntil(0.012, t0 + 0.40)
            s.transient(peak: 0.05)            // 벽 반사
            s.quiet(1.0)
            all.append(Case("단발 박수 + 400ms 벽 반사 (히스테리시스)", s, triggers: 0) {
                $0.onsetCount == 1 ? nil : "반사가 온셋이 됐다 — 온셋 \($0.onsetCount)개"
            })
        }

        // 5c. 40ms 간격 초기 반사 — 리프랙토리의 시험대.
        //
        //     딱딱한 표면 근처에서 박수를 치면 직접음과 초기 반사가 수십 ms
        //     간격으로 도착한다. 사람 귀에는 한 번인데 임계만 보면 두 번이다.
        //     짝 판정 창(300~600ms) 밖이라 그 자체로 오탐은 아니지만, 온셋
        //     타이밍을 오염시켜 다음 진짜 박수와 잘못 짝지어질 수 있다.
        //
        //     트리거가 아니라 **온셋 개수**를 검사해야 의미가 있다.
        //     refractorySeconds를 0으로 만들면 온셋이 2개가 되어 빨개진다.
        do {
            var s = Signal()
            s.quiet(2.0)
            let t0 = s.elapsed
            s.transient(peak: 0.4)
            s.levelUntil(0.001, t0 + 0.04)     // 릴리스될 만큼 낮게, 40ms만
            s.transient(peak: 0.3)             // 초기 반사
            s.quiet(1.5)
            all.append(Case("40ms 간격 초기 반사 (리프랙토리)", s, triggers: 0) {
                $0.onsetCount == 1 ? nil : "온셋 1을 기대했으나 \($0.onsetCount) — 리프랙토리 파손"
            })
        }

        // 6. 발소리 두 번, 500ms 간격. 0.014는 절대하한(0.018) 아래다.
        //    솔직한 한계: 큰 문 쾅 두 번이 300~600ms면 트리거된다. 짝 판정 창은
        //    오탐을 줄이지 없애지 않는다. 대가가 물고기 한 번 놀라는 것뿐이라
        //    감수한다.
        do {
            var s = Signal()
            s.quiet(2.0); s.pair(gap: 0.50, peak: 0.014); s.quiet(1.0)
            all.append(Case("발소리 2회 500ms", s, triggers: 0))
        }

        // 7. 정상 더블 클랩
        do {
            var s = Signal()
            s.quiet(2.0); s.pair(gap: 0.45, rt60: 0.4); s.quiet(1.0)
            all.append(Case("정상 더블 클랩 450ms", s, triggers: 1))
        }

        // 8. 삼연타 — 세 번째가 연쇄되면 안 된다.
        do {
            var s = Signal()
            s.quiet(2.0)
            let t0 = s.elapsed
            s.transient(peak: 0.4)
            s.quietUntil(t0 + 0.40); s.transient(peak: 0.4)
            s.quietUntil(t0 + 0.80); s.transient(peak: 0.4)
            s.quiet(1.0)
            all.append(Case("삼연타 (세 번째 연쇄 금지)", s, triggers: 1) {
                $0.onsetCount == 3 ? nil : "온셋 3을 기대했으나 \($0.onsetCount)"
            })
        }

        // 9~12. 짝 판정 창 경계 — 양 끝 모두
        for (gap, expected) in [(0.299, 0), (0.301, 1), (0.599, 1), (0.601, 0)] {
            var s = Signal()
            s.quiet(2.0); s.pair(gap: gap); s.quiet(1.0)
            let ms = Int((gap * 1000).rounded())
            all.append(Case("짝 판정 창 경계 \(ms)ms", s, triggers: expected))
        }

        // 13. 칩튠 배경. 스텝 어택이 바닥을 끌어올려 임계가 함께 올라가고,
        //     히스테리시스 덕에 지속음 구간에서 온셋이 반복되지 않는다.
        //     (라운지에선 m 키가 막혀 음악이 안 나오지만 --clap 단독 실행에선
        //      나올 수 있다.)
        do {
            var s = Signal()
            s.quiet(1.0)
            for _ in 0..<18 {              // ≈4s, 220ms 스텝
                s.level(0.09, 0.03)        // 플럭 어택
                s.level(0.03, 0.19)        // 감쇠 지속음
            }
            all.append(Case("칩튠 배경만 (짝 성립 없음)", s, triggers: 0))

            var s2 = Signal()
            s2.quiet(1.0)
            for _ in 0..<50 {              // ≈11s — 바닥 동결 해제까지 간다
                s2.level(0.09, 0.03)
                s2.level(0.03, 0.19)
            }
            s2.bed = 0.03
            s2.pair(gap: 0.45, peak: 0.5)
            s2.quiet(1.0)
            all.append(Case("칩튠 재생 중 더블 클랩", s2, triggers: 1))
        }

        // 14. 군중 연타 — 쿨다운이 발작을 막는가.
        do {
            var s = Signal()
            s.quiet(2.0)
            let t0 = s.elapsed
            for i in 0..<8 { s.quietUntil(t0 + Double(i) * 0.40); s.transient(peak: 0.4) }
            s.quiet(1.0)
            all.append(Case("군중 8연타 400ms 간격", s, triggers: 1))
        }

        // 15. NaN/Inf 버퍼를 맞고도 살아남는가 (몇 주짜리 무인 운영).
        do {
            var s = Signal()
            s.quiet(2.0)
            for _ in 0..<10 { s.append(Float.nan, hop) }
            for _ in 0..<5 { s.append(Float.infinity, hop) }
            s.quiet(1.0); s.pair(gap: 0.45); s.quiet(1.0)
            all.append(Case("NaN/Inf 버퍼 생존", s, triggers: 1) {
                $0.floor.isFinite ? nil : "바닥이 \($0.floor)가 됐다"
            })
        }

        // 16. 워밍업 창 안의 박수는 무시 (엔진 기동 인러시).
        do {
            var s = Signal()
            s.quiet(0.1); s.pair(gap: 0.45); s.quiet(0.2)
            all.append(Case("워밍업 창 안의 더블 클랩", s, triggers: 0) {
                $0.onsetCount == 2 ? nil : "온셋 2를 기대했으나 \($0.onsetCount)"
            })
        }

        return all
    }

    // MARK: - 러너

    /// - Returns: 전부 통과했으면 true.
    static func run() -> Bool {
        let list = cases()
        var failures = 0
        let hopMs = (hop * 1000 * 100).rounded() / 100
        print("ClapDetector 셀프테스트 — 홉 \(hopMs)ms, 임계 \(ClapDetector.onsetAbsMin)")
        for c in list {
            var detector = ClapDetector()
            var triggers = 0
            for sample in c.signal.samples {
                if detector.feed(rms: sample.rms, dt: sample.dt) { triggers += 1 }
            }
            var reason: String?
            if triggers != c.expectedTriggers {
                reason = "트리거 \(c.expectedTriggers)를 기대했으나 \(triggers)"
            } else {
                reason = c.extra?(detector)
            }
            if let reason {
                failures += 1
                print("  FAIL  " + c.name + " — " + reason)
            } else {
                print("  PASS  " + c.name)
            }
        }
        print(failures == 0
              ? "\(list.count)개 케이스 전부 통과"
              : "\(list.count)개 중 \(failures)개 FAILED")
        return failures == 0
    }
}
