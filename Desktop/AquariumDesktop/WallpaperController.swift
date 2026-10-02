import AppKit
import AquariumCore
import Combine
import Metal

/// 고른 모니터 하나의 바탕화면 아이콘 **뒤** 레이어에 borderless 창과 어항을 띄운다.
/// 마우스는 전부 통과시키고, 모든 Space에 고정한다.
///
/// 어항(World)은 하나다. 모니터를 바꾸면 같은 물고기가 새 화면 크기로 옮겨 간다 —
/// 세이브 소유자를 따로 정할 필요가 없다.
final class WallpaperController: ObservableObject {
    /// 터미널 버전과 같은 고정 tick (main.swift의 frameMicroseconds = 80ms, ~12.5fps).
    /// 물고기 이동이 tick당 증분이라 이 값이 곧 헤엄 속도다.
    static let tickInterval: TimeInterval = 0.08

    struct Display: Identifiable, Hashable {
        let id: String      // CGDisplay UUID — 재부팅·재연결에도 유지된다
        let name: String
    }

    /// 연결된 모니터 목록 (메뉴용).
    @Published private(set) var displays: [Display] = []
    /// 어항을 띄울 모니터. 기본값은 내장 디스플레이.
    @Published var selectedDisplayID: String? {
        didSet {
            guard selectedDisplayID != oldValue else { return }
            UserDefaults.standard.set(selectedDisplayID, forKey: Self.displayKey)
            rebuild()
        }
    }

    /// 수족관 켜기/끄기. 끄면 저장하고 창과 tick을 멈춘다.
    @Published var enabled: Bool = Settings.enabled {
        didSet {
            guard enabled != oldValue else { return }
            Settings.enabled = enabled
            enabled ? show() : hide()
        }
    }
    /// 메뉴 체크 표시용 — 어항 상태를 매번 비춘다.
    @Published private(set) var lighting: Lighting = .auto
    @Published private(set) var season: Season = .auto
    @Published private(set) var musicPlaying = false
    @Published private(set) var focusing = false
    @Published private(set) var fishCap = Settings.fishCap
    /// 지금 GPU로 그리고 있는지 (설정을 켜도 Metal을 못 쓰면 false).
    @Published private(set) var gpuActive = false
    @Published private(set) var gpuRendering = Settings.gpuRendering
    @Published private(set) var theme = Settings.theme
    /// 지금 열린 패널 (한 번에 하나). 열고 30초가 지나면 저절로 닫힌다.
    @Published private(set) var openPanel: PanelKind?
    private var panelOpenedAt = Date.distantPast
    static let panelLifetime: TimeInterval = 30

    enum PanelKind { case roster, mailbox, achievements, sponsor }
    /// 이 맥에서 Metal을 쓸 수 있는지.
    let gpuAvailable = MTLCreateSystemDefaultDevice() != nil

    private var world: World?
    private var window: NSWindow?
    private var view: TankRenderer?
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var started = false
    private let effects = DesktopEffects()
    private static let displayKey = "displayUUID"

    init() {
        selectedDisplayID = UserDefaults.standard.string(forKey: Self.displayKey)
        L10n.isKorean = Settings.korean
    }

    deinit {
        timer?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        for (center, token) in powerObservers { center.removeObserver(token) }
    }

    /// 앱이 뜬 뒤 한 번. 터미널 어항 가져오기를 먼저 물어봐야 해서 init과 나눴다.
    func start() {
        guard !started else { return }
        started = true
        displays = NSScreen.screens.map { Display(id: Self.uuid(of: $0), name: $0.localizedName) }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }
        observePower()
        if Probe.enabled, let name = ProcessInfo.processInfo.environment["AQUARIUM_PROBE_THEME"],
           let forced = Theme(rawValue: name) {
            theme = forced   // Probe: 설정을 건드리지 않고 테마를 본다
        }
        if enabled { show() }
        // Probe: 메뉴 없이 패널을 열어 확인한다 (AQUARIUM_PROBE_PANEL=roster|mailbox|achievements|sponsor).
        if Probe.enabled, let name = ProcessInfo.processInfo.environment["AQUARIUM_PROBE_PANEL"] {
            let kinds: [String: PanelKind] = ["roster": .roster, "mailbox": .mailbox,
                                              "achievements": .achievements, "sponsor": .sponsor]
            if let kind = kinds[name] { togglePanel(kind) }
        }
    }

    func save() { world?.writeSave() }

    // MARK: - 메뉴 동작 (터미널의 f·g·n·t·m 키)

    func feed() { world?.feed() }
    func feedLive() { world?.feedLive() }

    func setLighting(_ mode: Lighting) {
        world?.setLighting(mode)
        syncState()
    }

    func setSeason(_ mode: Season) {
        world?.setSeason(mode)
        syncState()
    }

    func toggleMusic() {
        world?.toggleMusic()
        syncState()
    }

    /// 집중(뽀모도로) — 상태줄에 남은 시간, 끝나면 먹이 잔치와 차임.
    func startFocus(minutes: Int) {
        world?.startFocus(minutes: minutes)
        syncState()
    }

    func cancelFocus() {
        guard world?.isFocusing == true else { return }
        world?.toggleFocus()
        syncState()
    }

    // MARK: - 패널 (도감·편지함·업적·후원)

    /// 같은 패널을 다시 고르면 닫는다. 도감·편지함·후원은 World의 패널 상태와 맞춘다 —
    /// 편지함을 열면 읽음 처리되는 것 같은 규칙을 터미널과 똑같이 따른다.
    func togglePanel(_ kind: PanelKind) {
        let opening = openPanel != kind
        closeWorldPanels()
        openPanel = opening ? kind : nil
        guard opening, let world else { return }
        switch kind {
        case .roster: world.toggleRoster()
        case .mailbox: world.toggleMailbox()
        case .sponsor: world.toggleSponsor()
        case .achievements: break   // 터미널엔 업적 패널이 없다(--achievements CLI) — 데스크톱 전용
        }
        panelOpenedAt = Date()
        if rendering { view?.panel = currentPanel(); view?.refresh() }
    }

    /// 후원 패널이 열려 있을 때 브라우저로 연다.
    func openSponsorPage() { world?.openSponsor() }

    private func closeWorldPanels() {
        guard let world else { return }
        if world.rosterOpen { world.toggleRoster() }
        if world.mailboxOpen { world.toggleMailbox() }
        if world.sponsorOpen { world.toggleSponsor() }
    }

    private func currentPanel() -> PanelContent? {
        guard let world, let openPanel else { return nil }
        if Date().timeIntervalSince(panelOpenedAt) > Self.panelLifetime {
            closeWorldPanels()
            self.openPanel = nil
            return nil
        }
        switch openPanel {
        case .roster: return world.rosterPanel()
        case .mailbox: return world.mailboxPanel()
        case .achievements: return world.achievementsPanel()
        case .sponsor: return world.sponsorPanel(openHint: L10n.sponsorOpenHintMenu)
        }
    }

    /// 테마를 바꾼다 — 색이 렌더러 버퍼·셰이더 팔레트에 박히므로 창을 새로 만든다.
    func setTheme(_ theme: Theme) {
        Settings.theme = theme
        self.theme = theme
        rebuild()
    }

    /// 낮·밤 자동 테마는 조명이 바뀌면 다시 칠한다 (1초마다 syncState에서 본다).
    private func applyThemeIfNeeded() -> Bool {
        let resolved = theme.resolved(isNight: world?.isNight ?? false)
        guard resolved != Palette.theme else { return false }
        Palette.apply(resolved)
        return true
    }

    /// 렌더러를 바꾼다 — 창을 새로 만들고 어항(World)은 그대로 이어받는다.
    func setGPURendering(_ on: Bool) {
        Settings.gpuRendering = on
        gpuRendering = on
        rebuild()
    }

    /// 정원을 바꾼다. 줄여도 있는 물고기는 그대로 — 번식만 멈춘다.
    func setFishCap(_ cap: Int) {
        Settings.fishCap = cap
        fishCap = cap
        world?.setFishCap(cap)
    }

    /// 언어를 바꾸면 상태줄 문구가 다음 tick부터 바뀐다 (L10n은 부를 때마다 고른다).
    func setKorean(_ korean: Bool) {
        Settings.korean = korean
        objectWillChange.send()
    }

    private func syncState() {
        guard let world else { return }
        if lighting != world.lighting { lighting = world.lighting }
        if season != world.season { season = world.season }
        if musicPlaying != effects.isMusicPlaying { musicPlaying = effects.isMusicPlaying }
        if focusing != world.isFocusing { focusing = world.isFocusing }
        if theme == .automatic, view != nil,
           theme.resolved(isNight: world.isNight) != Palette.theme { rebuild() }
    }

    private func show() {
        guard started else { return }
        rebuild()
        guard timer == nil else { return }
        rendering = true
        schedule(interval: Self.tickInterval)
        updateRendering()
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        world?.writeSave()
        window?.orderOut(nil)
        window = nil
        view = nil
    }

    private func tick() {
        ticks += 1
        if rendering {
            let t0 = Probe.now()
            world?.update()
            Probe.add("update", since: t0)
            let t1 = Probe.now()
            view?.panel = currentPanel()
            view?.refresh()
            Probe.add("refresh(total)", since: t1)
            Probe.frame()
            // 보이는 동안은 가려졌는지 1초에 한 번만 본다 — 멈추는 건 조금 늦어도 된다.
            // 메뉴 상태(집중 완료 등 어항이 스스로 바꾸는 값)도 그때 맞춘다.
            if ticks % Self.ticksPerSecond == 0 {
                syncState()
                updateRendering()
            }
        } else {
            // 멈춘 동안은 다시 보이는지를 0.2초마다 본다 — 재개는 빨라야 한다.
            // 시뮬레이션은 1초에 한 번이면 된다.
            if ticks % Self.idleTicksPerUpdate == 0 {
                world?.update()
                syncState()
            }
            updateRendering()
        }
    }

    // MARK: - 배터리 절약

    /// 보이지 않을 때는 0.2초마다 깨어 다시 보이는지 확인하고, 시뮬레이션은 1초에 한 번만
    /// 굴린다 — 자동 저장·자동 먹이·번식 타이머(전부 systemUptime 기준)는 그대로 돌고,
    /// 헤엄은 보는 사람이 없다. (처음엔 1초 간격이었는데 재개가 굼뜨게 느껴졌다.)
    static let idleInterval: TimeInterval = 0.2
    private static let idleTicksPerUpdate = 5
    private static let ticksPerSecond = Int((1 / tickInterval).rounded())

    /// 지금 그리고 있는지. 가려짐·잠금·디스플레이 잠자기 중 하나면 false.
    private(set) var rendering = true
    private var screenLocked = false
    private var displaysAsleep = false
    private var ticks = 0
    private var powerObservers: [(NotificationCenter, NSObjectProtocol)] = []

    private func observePower() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping (WallpaperController) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                body(self)
                self.updateRendering()
            }
            powerObservers.append((center, token))
        }
        on(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaysAsleep = true }
        on(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaysAsleep = false }
        on(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.screenLocked = true }
        on(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.screenLocked = false }
        on(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        on(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
    }

    /// 바탕화면 레벨 창은 NSWindow.occlusionState가 다른 앱 창에 100% 덮여도 .visible로
    /// 남는다(스파이크 실측). 그래서 창 목록으로 그리드가 얼마나 덮였는지 직접 본다.
    private func updateRendering() {
        guard let window, let view else { return }
        let grid = window.convertToScreen(view.convert(view.bounds, to: nil))
        // Probe 중에는 가려져도 계속 그린다 — 렌더 비용은 보이든 말든 같다.
        let covered = !Probe.enabled && DesktopCoverage.fraction(of: grid, excludingPID: getpid()) >= 0.98
        let shouldRender = !covered && !screenLocked && !displaysAsleep
        guard shouldRender != rendering else { return }
        rendering = shouldRender
        if rendering { view.refresh() }
        schedule(interval: rendering ? Self.tickInterval : Self.idleInterval)
    }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        ticks = 0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 모니터 연결·해제·해상도 변경·선택 변경 때마다 창을 새로 만들고, 어항은
    /// 이어받아 크기만 맞춘다 — 해상도를 바꿀 때마다 물고기가 새로 태어나면 안 된다.
    private func rebuild() {
        let screens = NSScreen.screens
        displays = screens.map { Display(id: Self.uuid(of: $0), name: $0.localizedName) }
        guard enabled, started else { return }
        guard let screen = Self.pick(from: screens, preferred: selectedDisplayID) else { return }

        let visible = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        _ = applyThemeIfNeeded()
        let metrics = CellMetrics(pointSize: Self.fontSize(for: screen), scale: screen.backingScaleFactor)
        let view: TankRenderer = Self.makeRenderer(gpu: gpuRendering, visible: visible, metrics: metrics)
        gpuActive = view is MetalTankView
        if let world {
            if world.cols != view.cols || world.rows != view.rows {
                world.resize(cols: view.cols, rows: view.rows)
            }
        } else {
            world = makeWorld(cols: view.cols, rows: view.rows)
        }
        view.world = world
        view.panel = currentPanel()
        view.refresh()

        window?.orderOut(nil)
        window = makeWindow(for: screen, tank: view)
        self.view = view
        syncState()
    }

    /// AQUARIUM_RENDERER=cpu|metal은 측정용으로 설정을 덮어쓴다.
    private static func makeRenderer(gpu: Bool, visible: CGRect, metrics: CellMetrics) -> TankRenderer {
        let forced = ProcessInfo.processInfo.environment["AQUARIUM_RENDERER"]
        if forced != "cpu", gpu || forced == "metal",
           let metal = MetalTankView(visibleRect: visible, metrics: metrics) {
            return metal
        }
        return TankView(visibleRect: visible, metrics: metrics)
    }

    /// 선택한 모니터 → 없으면 내장 디스플레이 → 없으면 첫 화면.
    private static func pick(from screens: [NSScreen], preferred: String?) -> NSScreen? {
        if let preferred, let match = screens.first(where: { uuid(of: $0) == preferred }) { return match }
        return screens.first(where: { CGDisplayIsBuiltin(displayID(of: $0)) != 0 }) ?? screens.first
    }

    private func makeWorld(cols: Int, rows: Int) -> World {
        // lounge 그대로(정원 120·번식 2~3일·자동 먹이). QR은 렌더러가 그리지 않는다.
        // 터미널 큐는 소비하지 않는다 — 같은 큐를 두 어항이 먹으면 먼저 읽은 쪽이 가져간다.
        let config = RunConfig(lounge: true, terminalDark: nil,
                               storage: Storage(saveURL: Self.saveURL, pollsTerminalQueues: false),
                               fishCap: Settings.fishCap)
        return World(cols: cols, rows: rows, config: config,
                     restoring: SaveStore.load(from: Self.saveURL), effects: effects)
    }

    private func makeWindow(for screen: NSScreen, tank: NSView) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        // 바탕화면 아이콘 레벨(.desktopIconWindow)보다 아래.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = NSColor(cgColor: Palette.background) ?? .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        // 화면 전체는 단색 레이어(백킹 버퍼 없음), 글리프는 그리드 크기 뷰에만 그린다.
        let container = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = Palette.background
        container.addSubview(tank)
        window.contentView = container
        window.orderFront(nil)
        return window
    }

    /// 레티나 내장 디스플레이는 가까이서 보니 같은 포인트 크기가 작아 보인다.
    private static func fontSize(for screen: NSScreen) -> CGFloat {
        CGDisplayIsBuiltin(displayID(of: screen)) != 0 ? 15 : 13
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private static func uuid(of screen: NSScreen) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID(of: screen))?.takeRetainedValue() else {
            return "\(displayID(of: screen))"
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// 데스크톱 전용 세이브. 터미널(~/.aquarium.json)과 섞지 않는다.
    /// Probe 중에는 AQUARIUM_DESKTOP_SAVE로 사본을 쓸 수 있다 — FileManager는 HOME 환경 변수를
    /// 따르지 않아, 임시 HOME으로는 실제 세이브를 못 피한다(편지함 테스트가 읽음 처리를 남겼다).
    static var saveURL: URL {
        if Probe.enabled, let path = ProcessInfo.processInfo.environment["AQUARIUM_DESKTOP_SAVE"] {
            return URL(fileURLWithPath: path)
        }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AquariumDesktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("save.json")
    }
}
