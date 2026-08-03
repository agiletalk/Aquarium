import Foundation

/// 더블 클랩 판정기 — 순수 상태 기계.
///
/// AVFoundation도 시계도 모른다. 입력이 (rms, dt) 쌍뿐이라 마이크 없이
/// 합성 시퀀스로 전 경로를 결정론적으로 돌릴 수 있다 (ClapSelfTest).
///
/// **오디오 스레드에서만 mutate한다.** 메인 스레드는 이 구조체를 절대 만지지
/// 않는다 — Music.swift의 songIndex가 렌더 스레드와 메인 양쪽에서 동기화 없이
/// 오가는 기존 레이스가 있는데, 그걸 따라하지 않는다.
struct ClapDetector {

    // MARK: - 튜닝 상수
    //
    // 전부 이름을 붙인다. ClapSelfTest의 픽스처가 이 값들을 근거로 짜여 있어서,
    // 값을 바꾸면 어느 픽스처가 왜 빨개지는지 추적할 수 있다.

    /// 노이즈 바닥 대비 몇 배여야 트랜지언트로 볼지. 6배 ≈ +15.6 dB.
    static let onsetRatio: Float = 6

    /// 비율과 무관하게 넘어야 하는 **절대 하한**.
    ///
    /// 조용한 방에서는 바닥이 0으로 수렴하므로 "바닥의 6배"가 종이 넘기는
    /// 소리에도 성립한다. 이 상수가 그걸 막는다.
    ///
    /// 0.018은 실측값이다 (2026-08-03, MacBook Pro 내장 마이크, 512프레임 홉):
    ///   사무실 정적 6초 562홉 → mean 0.00269 / p95 0.00467 / **MAX 0.01272**
    ///   근거리 박수          → **피크 0.09676**
    /// ambient 천장 바로 위(1.4배)에 놓았다. 한때 기하평균인 0.030을 골랐다가
    /// 되돌렸다 — 기하평균은 양방향 실패 비용이 대등할 때 쓰는 기준인데
    /// 여기선 대등하지 않다. 임계가 낮으면 물고기가 가끔 괜히 놀라고(귀엽고,
    /// 3초 불응기가 발작을 막는다), 높으면 **먼 박수가 영원히 안 잡혀 전시가
    /// 죽은 것처럼 보인다.** 게다가 실측은 마이크 0.5m 거리라, 라운지의 2~3m
    /// 에서는 같은 박수가 ~0.019로 들어온다 — 0.030이면 그걸 통째로 놓친다.
    ///
    /// 거리에 따른 레벨 변화는 원래 상대 게이트(onsetRatio × 적응형 바닥)의
    /// 몫이다. 절대 하한은 "거의 무음이면 뭐든 6배"라는 병리만 막는 장치라서
    /// ambient 피크 바로 위가 제 위치다.
    ///
    /// 라운지 음향은 여기서 알 수 없으므로 env로 뺀다 — AQUARIUM_LOUNGE_QR과
    /// 같은 성격의 "재빌드 없는 현장 노브"다. 테스트 훅이 아니라 운영 노브라
    /// --help와 세팅 문서에 싣는다.
    static let onsetAbsMin: Float = {
        if let raw = ProcessInfo.processInfo.environment["AQUARIUM_CLAP_THRESHOLD"],
           let v = Float(raw), v.isFinite, v > 0, v < 1 { return v }
        return 0.018
    }()

    /// 다음 온셋을 무장하려면 임계의 이 비율 아래까지 떨어져야 한다(히스테리시스).
    ///
    /// **잔향 대응의 핵심이다.** 라운지처럼 반사가 긴 공간에서 박수 꼬리는
    /// 수백 ms에 걸쳐 임계선 근처를 오르내리는데, 그 재교차가 300~600ms 창에
    /// 들어오면 박수 한 번이 더블 클랩으로 둔갑한다. 릴리스를 임계의 0.4배로
    /// 낮춰두면 꼬리는 다시 임계까지 못 올라온다.
    static let releaseFactor: Float = 0.4

    /// 한 번의 박수가 초기 반사음 때문에 N개 온셋으로 쪼개지지 않게.
    /// 사람이 낼 수 있는 최소 박수 간격보다 훨씬 짧아(120ms < 300ms) 정상
    /// 더블 클랩을 절대 막지 않는다.
    static let refractorySeconds: Double = 0.12

    /// 더블 클랩 짝 판정 창. 오너 합의값이라 임의로 못 바꾼다.
    /// 양 끝 모두 픽스처가 있다 (299/301/599/601 ms).
    static let pairMinSeconds: Double = 0.30
    static let pairMaxSeconds: Double = 0.60

    /// 트리거 후 침묵. 관중이 몰려도 수조가 발작하지 않게, 그리고 효과음이
    /// 스피커로 나가 마이크로 되먹임되는 경로를 시간으로 잘라내기 위해.
    /// World.clap()의 불응기(3초)와 같은 값이지만 서로 독립이다 — 둘 중 하나가
    /// 없어도 나머지가 성립한다.
    static let cooldownSeconds: Double = 3.0

    /// 바닥 EMA 시상수. **올라갈 땐 느리게, 내려올 땐 빠르게.**
    /// 빠른 하강이 "박수가 바닥을 끌어올려 수조가 귀머거리가 된다"의 실질적
    /// 치료제다 — 설령 바닥이 올라가도 방이 조용해지면 2초 안에 회복한다.
    static let floorTauUp: Double = 4.0
    static let floorTauDown: Double = 0.5

    /// 임계 위에 이만큼 연속으로 머물면 박수가 아니라 방이 시끄러워진 것이다.
    /// 동결을 풀어 따라간다. 8초는 어떤 박수보다 길고 어떤 환경 변화보다 짧다.
    static let floorUnstickSeconds: Double = 8.0

    /// 바닥 클램프. 하한은 "0에 수렴한 바닥 × 6 = 아무 소리나 통과"를 막고,
    /// 상한은 "한 번 올라간 바닥이 영원히 수조를 귀머거리로 만든다"를 막는다.
    /// 실패의 비대칭이 근거다 — 시끄러운 방에서 가끔 놀라는 건 귀엽지만
    /// 몇 주 동안 반응이 없는 건 전시가 죽은 것이다.
    static let floorMin: Float = 0.0015
    static let floorMax: Float = 0.05

    /// 엔진 기동 직후 HAL 인러시·DC 오프셋으로 개장하자마자 놀라지 않게.
    static let warmupSeconds: Double = 1.0

    /// dt 이상치 방어. 오디오 쪽은 항상 고정 홉을 넘기지만 계약은 계약이다.
    static let maxDtSeconds: Double = 0.5

    // MARK: - 상태

    /// 픽스처 검증용 — "박수 뒤에 바닥이 걸어 올라가지 않았는가".
    private(set) var floor: Float = ClapDetector.floorMax

    /// 픽스처 검증용 — "트리거는 0인데 온셋이 3개"를 잡아야 히스테리시스를
    /// 테스트할 수 있다.
    private(set) var onsetCount = 0

    private var hot = false              // 현재 임계 위인가 (히스테리시스 반영)
    private var hotFor: Double = 0       // 연속으로 임계 위에 머문 시간
    private var sinceOnset: Double = Self.never
    private var armed = false            // 첫 박수가 짝을 기다리는 중
    private var cooldown: Double = 0
    private var warmup: Double = ClapDetector.warmupSeconds

    /// "아직 온셋이 없다"를 나타내는 sentinel. 어떤 판정 창보다 크기만 하면 된다.
    private static let never: Double = 1e9

    init() {}

    /// - Parameters:
    ///   - rawRMS: 분석 홉 하나의 선형 RMS (풀스케일 1.0)
    ///   - rawDt:  그 홉의 길이(초). 오디오 쪽은 frameLength/sampleRate로 만든다.
    /// - Returns: 이번 홉에서 더블 클랩이 확정됐으면 true.
    mutating func feed(rms rawRMS: Float, dt rawDt: Double) -> Bool {
        // NaN 방어. 드라이버가 NaN을 한 번만 흘려도 floor가 NaN이 되고 그 뒤로
        // 모든 비교가 false가 되어 몇 주짜리 전시가 조용히 죽는다. 무인 운영에서
        // 이 한 줄이 나머지 전부만큼 중요하다.
        guard rawRMS.isFinite, rawDt.isFinite, rawDt > 0 else { return false }
        let rms = max(0, rawRMS)
        let dt = min(rawDt, Self.maxDtSeconds)

        // 1) 타이머
        if warmup > 0 { warmup = max(0, warmup - dt) }
        if cooldown > 0 {
            cooldown = max(0, cooldown - dt)
            // 쿨다운이 끝나는 순간 묵은 짝이 터지지 않게 완전히 비운다.
            if cooldown == 0 { armed = false; sinceOnset = Self.never }
        }
        if sinceOnset < Self.never { sinceOnset += dt }
        if armed, sinceOnset > Self.pairMaxSeconds { armed = false }

        // 2) 임계 — 이번 홉의 에너지가 바닥에 섞이기 **전** 값으로 판단한다.
        //    max(비율, 절대하한)이 핵심. 둘 중 높은 쪽이 이긴다.
        let threshold = max(floor * Self.onsetRatio, Self.onsetAbsMin)
        let releaseLevel = threshold * Self.releaseFactor

        // 3) 히스테리시스 에지 검출. 온셋은 **상승 에지**에서만 난다.
        //    그래서 지속적인 박수갈채는 N개가 아니라 정확히 1개의 온셋을 만들고,
        //    감쇠 꼬리는 0개를 만든다.
        var onset = false
        if hot {
            if rms < releaseLevel {
                hot = false
                hotFor = 0
            } else {
                hotFor += dt
            }
        } else if rms > threshold {
            hot = true
            hotFor = dt
            onset = sinceOnset >= Self.refractorySeconds
        }

        // 4) 바닥 갱신 — hot이면 동결한다.
        //    박수·환호가 바닥을 끌어올려 수조를 귀머거리로 만드는 게 라운지의
        //    실패 모드다. 다만 8초 넘게 계속 뜨거우면 박수가 아니라 방이 바뀐
        //    것이라 다시 따라간다. 그렇게 올라간 바닥도 floorTauDown 덕에 방이
        //    조용해지면 2초 안에 되돌아온다.
        if !hot || hotFor > Self.floorUnstickSeconds {
            let tau = rms > floor ? Self.floorTauUp : Self.floorTauDown
            let alpha = Float(1 - exp(-dt / tau))   // dt에 무관한 시상수 EMA
            floor += alpha * (rms - floor)
            floor = min(max(floor, Self.floorMin), Self.floorMax)
        }

        guard onset else { return false }
        onsetCount += 1
        let gap = sinceOnset          // 리셋 전에 잡아야 한다
        sinceOnset = 0

        // 워밍업·쿨다운 중에는 온셋 타이밍만 추적하고 짝은 만들지 않는다.
        guard warmup <= 0, cooldown <= 0 else {
            armed = false
            return false
        }

        if armed, gap >= Self.pairMinSeconds, gap <= Self.pairMaxSeconds {
            armed = false
            // 세 번째 박수가 연쇄되지 않게 짝 상태를 비운다.
            //
            // 정직하게 적자면 이 한 줄은 **오늘은 잉여다.** 위쪽 쿨다운 만료
            // 분기가 같은 초기화를 하고, cooldownSeconds(3.0) > pairMaxSeconds
            // (0.60)라 그 사이에 짝이 성립할 수 없다. 변이 테스트로 확인했다 —
            // 이 줄만 지워도 픽스처 19개가 전부 통과한다.
            //
            // 그래도 남기는 이유: cooldownSeconds를 0으로 낮추는 순간 쿨다운
            // 만료 분기(`if cooldown > 0`)가 아예 안 돌아서 이 줄이 유일한
            // 방어선이 된다. 두 상수의 관계에 기대는 불변식을 한 곳에만 두지
            // 않으려는 것이다. 셀프테스트가 이걸 덮지 못한다는 점도 같이 안다.
            sinceOnset = Self.never
            cooldown = Self.cooldownSeconds
            return true
        }

        // 짝이 안 맞은 온셋(첫 박수 / 너무 빠름 / 너무 늦음)은 새 후보가 된다.
        armed = true
        return false
    }
}
