import AppKit
import AquariumCore
import Combine

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

    private var world: World?
    private var window: NSWindow?
    private var view: TankView?
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private let effects = DesktopEffects()
    private static let displayKey = "displayUUID"

    init() {
        selectedDisplayID = UserDefaults.standard.string(forKey: Self.displayKey)
        rebuild()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }

        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func save() { world?.writeSave() }

    private func tick() {
        world?.update()
        view?.refresh()
    }

    /// 모니터 연결·해제·해상도 변경·선택 변경 때마다 창을 새로 만들고, 어항은
    /// 이어받아 크기만 맞춘다 — 해상도를 바꿀 때마다 물고기가 새로 태어나면 안 된다.
    private func rebuild() {
        let screens = NSScreen.screens
        displays = screens.map { Display(id: Self.uuid(of: $0), name: $0.localizedName) }
        guard let screen = Self.pick(from: screens, preferred: selectedDisplayID) else { return }

        let visible = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let view = TankView(visibleRect: visible, metrics: CellMetrics(pointSize: Self.fontSize(for: screen)))
        if let world {
            if world.cols != view.cols || world.rows != view.rows {
                world.resize(cols: view.cols, rows: view.rows)
            }
        } else {
            world = makeWorld(cols: view.cols, rows: view.rows)
        }
        view.world = world
        view.refresh()

        window?.orderOut(nil)
        window = makeWindow(for: screen, tank: view)
        self.view = view
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
                               storage: Storage(saveURL: Self.saveURL, pollsTerminalQueues: false))
        return World(cols: cols, rows: rows, config: config,
                     restoring: SaveStore.load(from: Self.saveURL), effects: effects)
    }

    private func makeWindow(for screen: NSScreen, tank: TankView) -> NSWindow {
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
    static var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AquariumDesktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("save.json")
    }
}
