import AVFoundation
import Foundation
import os   // os_unfair_lock

/// 마이크 → RMS → ClapDetector → 플래그. AVFoundation에 닿는 유일한 지점.
///
/// **싱글턴이 아니다.** MusicPlayer.shared는 World가 손을 뻗기 때문에 있는
/// 것이고 여기는 정확히 반대여야 한다 — main.swift가 만들고 main.swift가
/// 폴링하고 World는 존재를 모른다. 싱글턴이면 Card.swift의 헤드리스 World가
/// `aquarium --card` 도중에 오디오 HAL과 마이크 표시등을 켤 수 있다.
/// Slack poller가 --adopt만 아는 것과 같은 경계다.
///
/// **자기 AVAudioEngine을 따로 갖는다.** AVAudioEngine.h가 입출력 모드를
/// 오가는 앱에는 두 인스턴스가 유리하다고 권고한다. 공유하면 m 키 한 번
/// (engine.stop())이 마이크까지 멈추고, 음악만 켜도 마이크 표시등이 켜지고,
/// 한쪽 실패가 다른 쪽을 죽인다. 라운지에선 음악이 막혀 안 보이지만
/// --clap 단독 실행에서 바로 터진다.
final class ClapListener {

    /// 512프레임 ≈ 10.7ms @48kHz.
    ///
    /// **탭이 주는 버퍼 크기에 의존하지 않는다.** AVAudioNode.h는 bufferSize의
    /// 지원 범위를 100~400ms로 적어놨고 실제로 무엇이 오는지는 기기·OS마다
    /// 다르다. 그런데 박수 트랜지언트는 수 ms짜리다 — 100ms 창으로 RMS를 내면
    /// 박수 에너지가 침묵에 희석돼 비율 판정이 성립하지 않고, 리프랙토리
    /// (120ms)와 짝 판정 창(300~600ms)이 버퍼 크기 단위로 양자화된다.
    /// 들어온 버퍼가 몇이든 여기서 고정 홉으로 다시 자른다. 결과: dt가 항상
    /// 일정하고, 시간 해상도가 하드웨어와 무관해지고, 셀프테스트 픽스처와
    /// 실제 동작이 같은 격자 위에 놓인다.
    private static let hopFrames = 512

    /// 요청값일 뿐이다. 헤더 권장 범위 안쪽으로 잡되, 위 이유로 실제 크기는
    /// 판정 결과에 영향을 주지 않는다.
    private static let requestedBufferFrames: AVAudioFrameCount = 4096

    private let engine = AVAudioEngine()

    // ── 오디오 스레드 전용 (메인은 읽지도 쓰지도 않는다) ──
    private var detector = ClapDetector()
    private var hopSumSquares: Double = 0
    private var hopFilled = 0
    private var hopDt: Double = 0        // start()에서 1회 세팅, 이후 읽기 전용
    /// sawSignal을 이미 올렸는지 — **오디오 스레드 로컬 사본**이다.
    /// 이게 없으면 락 트래픽이 초당 94회가 된다(ambient가 floorMin을 거의 항상
    /// 넘으므로 alive가 매 홉 true다). 그러면 정작 clapped=true인 그 한 홉에서
    /// trylock이 실패해 박수가 조용히 사라질 확률이 올라간다. 첫 신호에서 한 번만
    /// 락을 잡고 그 뒤로는 건드리지 않는다.
    private var signalledOnce = false

    // ── 스레드 경계를 넘는 상태 (lock으로 보호) ──
    //
    // os_unfair_lock은 **주소가 고정돼야** 한다. Swift 저장 프로퍼티로 두고
    // os_unfair_lock_lock(&self.lock)을 하면 inout 접근이 임시 복사본의 주소를
    // 넘길 수 있고, 그러면 락은 컴파일도 되고 실행도 되지만 아무것도 지키지
    // 않는다. 힙에 한 번 잡아두고 그 포인터만 쓴다.
    //
    // macOS 12 타깃이라 OSAllocatedUnfairLock(13+)은 못 쓰고, Swift Atomics는
    // 패키지 의존성이라 못 쓴다(의존성 0 철학).
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private var pendingClap = false
    private var sawSignal = false
    private var engineStarted = false

    init() {
        lock.initialize(to: os_unfair_lock())
    }

    // deinit / stop()을 두지 않는다. 수명이 프로세스와 같고, 해제하면 오디오
    // 스레드가 이미 죽은 락을 잡을 수 있다. main.swift의 shutdown()에도 엔진
    // 정리를 넣지 않는다 — 그 핸들러는 이미 async-signal-unsafe한데 거기에
    // AVFoundation 호출을 더할 이유가 없다. exit(0)이 HAL을 정리한다.

    /// **권한 승인 + 포맷 유효 + 엔진 기동 + 실제 신호 도착**이 전부 성립했는가.
    ///
    /// "--clap을 줬다"와 엄격히 다르고, "권한이 있다"와도 다르다.
    /// 상태줄 표시자와 라운지 힌트는 오직 이 값만 본다 — 마이크가 죽은 전시가
    /// 몇 주 동안 방문객에게 "박수를 쳐보세요"라고 말하면 안 된다.
    ///
    /// **신호 기반인 게 핵심이다.** 실측(2026-08-03)에서 번들 없는 CLI의
    /// AVCaptureDevice.authorizationStatus가 notDetermined를 반환하는데 탭은
    /// 실제 오디오를 흘렸다(peak 0.179) — 상태 조회는 호출한 코드의 TCC
    /// 레코드를 보는데 bare 바이너리엔 그게 없고, 실제 접근은 책임 프로세스
    /// (터미널 앱)의 승인으로 결정된다. 권한 API를 신뢰하면 작동하는 마이크를
    /// 꺼버린다. 하드웨어 뮤트나 신호 없는 가상 입력(BlackHole 등)도 이 값으로
    /// 정직하게 드러난다.
    var isLive: Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return engineStarted && sawSignal
    }

    /// 실패해도 절대 exit하지 않는다 — 수조는 그대로 돌고 박수만 꺼진다.
    /// 반드시 term.setup() **이전에** 호출한다.
    /// - Returns: 엔진이 돌기 시작했는가. (신호 도착은 별개 — isLive 참고)
    @discardableResult
    func start() -> Bool {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // 마이크가 없는 맥(라운지 후보인 Mac mini!)은 sampleRate 0 /
        // channelCount 0 포맷을 준다. 그 상태로 installTap을 부르면 **ObjC
        // 예외**가 나고 Swift는 잡을 수 없다 → 무인 전시가 하드 크래시한다.
        // AVAudioEngine.h가 명시적으로 지시하는 검사다.
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }

        hopDt = Double(Self.hopFrames) / format.sampleRate

        input.installTap(onBus: 0,
                         bufferSize: Self.requestedBufferFrames,
                         format: format) { [unowned self] buffer, _ in
            self.process(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            // 장치가 사라졌거나 배타 점유 중. 탭을 걷고 조용히 포기한다.
            input.removeTap(onBus: 0)
            return false
        }
        os_unfair_lock_lock(lock)
        engineStarted = true
        os_unfair_lock_unlock(lock)
        return true
    }

    /// 신호가 실제로 도착할 때까지 기다린다(최대 timeout).
    /// 보통 수십 ms 안에 붙으므로 정상 경로는 빠르다 — 느린 건 실패 경로뿐이다.
    /// 프리플라이트에서 안내 문구를 고르려면 이 답이 필요하다.
    func waitForSignal(timeout: Double) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if isLive { return true }
            usleep(20_000)
        }
        return isLive
    }

    /// 렌더 루프가 프레임마다 부른다. 소비형 — 한 번 true를 주면 플래그를 내린다.
    ///
    /// 메인은 **정상 락**을 쓴다. 오디오 쪽이 이 락을 잡는 구간은 대입 몇 줄이라
    /// 대기가 나노초 단위고, 오디오 쪽은 애초에 trylock이라 절대 안 막힌다 —
    /// 우선순위 역전이 성립할 수 없는 방향으로만 대기가 일어난다.
    func consumeClap() -> Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        guard engineStarted, pendingClap else { return false }
        pendingClap = false
        return true
    }

    /// 오디오 스레드. **할당 금지, 블로킹 금지, 로그 금지.**
    private func process(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        // floatChannelData는 포맷이 float가 아니면 nil이다. 원 스케치의
        // `buf.floatChannelData![0]` 강제 언랩은 무인 전시에서 크래시가 된다.
        guard frames > 0, let channels = buffer.floatChannelData else { return }
        let samples = channels[0]        // 0번 채널만 쓴다 (믹스다운 불필요)
        let frameStride = buffer.stride  // 비인터리브면 1, 인터리브면 채널 수

        var index = 0
        while index < frames {
            let take = min(Self.hopFrames - hopFilled, frames - index)
            var sum = hopSumSquares
            var j = 0
            while j < take {
                let s = Double(samples[(index + j) * frameStride])
                sum += s * s
                j += 1
            }
            hopSumSquares = sum
            hopFilled += take
            index += take

            // 홉이 덜 찼으면 다음 버퍼로 이월한다 — 버퍼 경계에서 시간이 새면
            // 짝 판정 창이 어긋난다.
            if hopFilled < Self.hopFrames { break }

            let rms = Float((hopSumSquares / Double(Self.hopFrames)).squareRoot())
            hopSumSquares = 0
            hopFilled = 0

            let clapped = detector.feed(rms: rms, dt: hopDt)
            // 첫 신호만 보고한다 (위 signalledOnce 주석 참고).
            let firstSignal = !signalledOnce && rms.isFinite && rms > ClapDetector.floorMin

            guard clapped || firstSignal else { continue }

            // trylock: 못 잡으면 이번 박수는 버린다. 사람은 다시 친다.
            // Persistence의 FileLock이 LOCK_NB·재시도 0을 쓰는 것과 같은
            // 판단이고, 여기선 이유가 더 강하다 — 오디오 스레드가 블록되면
            // 프레임을 놓치고 스피커에서 딸깍 소리가 난다.
            if os_unfair_lock_trylock(lock) {
                if clapped { pendingClap = true }
                if firstSignal {
                    sawSignal = true
                    signalledOnce = true
                }
                os_unfair_lock_unlock(lock)
            }
            // trylock 실패 시 signalledOnce를 올리지 않으므로 다음 홉에 다시 시도한다.
        }
    }
}

/// 마이크 권한 프리플라이트. **term.setup() 이전에만** 부른다.
///
/// ⚠️ 상태 조회를 *게이트*로 쓰지 않는다. 실측에서 authorizationStatus가
/// notDetermined인데 오디오가 흘렀다 — 상태를 믿고 갈래를 나누면 작동하는
/// 마이크를 꺼버린다. 상태는 **안내 문구를 고르는 용도로만** 쓰고, 진짜 판정은
/// 항상 "탭을 걸어보고 샘플이 오는가"다.
enum ClapPermission {

    /// 마이크를 열고 신호가 오는지까지 확인한다. 어떤 갈래에서도 exit하지 않는다.
    /// - Returns: 박수 감지가 살아났는가. false면 호출자는 안내만 찍고 계속 간다.
    static func bringUp(_ listener: ClapListener) -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        // 정책(MDM·스크린타임)으로 막힌 경우만 조기 종료한다. 여기서만 시도가
        // 무의미하다 — 사용자가 설정으로 풀 수 있는 문제가 아니다.
        if status == .restricted {
            print(L10n.clapRestricted)
            return false
        }

        // 첫 실행이면 프롬프트를 띄운다. 프롬프트가 터미널 앱 이름으로 뜨는 걸
        // 미리 알려줘야 사람이 "왜 갑자기 iTerm이?" 하며 거절하지 않는다.
        if status == .notDetermined {
            print(L10n.clapPrompting)
            fflush(stdout)
            // 결과가 false여도 포기하지 않는다 — 아래에서 어차피 탭을 걸어본다.
            _ = requestAccess()
        }

        guard listener.start() else {
            // 포맷이 0채널이면 입력 장치가 아예 없다. 그 외는 engine.start() 실패.
            print(AVCaptureDevice.default(for: .audio) == nil
                  ? L10n.clapNoMicrophone : L10n.clapEngineFailed)
            return false
        }

        // 진짜 판정. 정상 경로는 수십 ms 안에 붙는다.
        if listener.waitForSignal(timeout: 1.5) { return true }

        // 엔진은 도는데 신호가 0이다. 상태에 맞는 안내를 고른다.
        print(status == .denied ? L10n.clapDenied : L10n.clapSilentInput)
        return false
    }

    private static func requestAccess() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            granted = ok
            semaphore.signal()
        }
        // 완료 핸들러는 메인 큐가 아닌 임의 큐에서 오므로 메인을 세워도 데드락이
        // 아니다 — 실측에서 1.8초(iTerm2)·8.9초(Terminal.app)에 정상 반환했다.
        // 타임아웃은 그 가정이 틀렸을 때의 안전망이다. 최악이 "60초 뒤 박수
        // 꺼짐"이지 "전시가 영원히 멈춤"이 아니다.
        if semaphore.wait(timeout: .now() + 60) == .timedOut {
            print(L10n.clapPromptTimedOut)
            return false
        }
        return granted
    }
}
