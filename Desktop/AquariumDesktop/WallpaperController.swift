import AppKit

/// 화면마다 바탕화면 아이콘 **뒤** 레이어에 borderless 창 하나.
/// 마우스는 전부 통과시키고, 모든 Space에 고정한다.
final class WallpaperController {
    private var windows: [NSWindow] = []
    private var observer: NSObjectProtocol?

    init() {
        rebuild()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// 모니터 연결·해제·해상도 변경 때마다 통째로 다시 만든다. 화면 수가 적고
    /// 드물게 일어나는 일이라 창을 재사용하며 맞추는 것보다 단순하고 틀릴 일이 없다.
    private func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.enumerated().map { index, screen in
            makeWindow(for: screen, index: index)
        }
    }

    private func makeWindow(for screen: NSScreen, index: Int) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        // 바탕화면 아이콘 레벨(.desktopIconWindow)보다 아래.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.contentView = SpikeView(screen: screen, index: index)
        window.orderFront(nil)
        return window
    }
}
