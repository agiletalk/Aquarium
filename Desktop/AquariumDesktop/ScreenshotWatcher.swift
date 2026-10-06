import Foundation

/// 스크린샷 먹이 — 스크린샷 저장 폴더를 지켜보다가 새 스크린샷이 생기면 알린다.
///
/// Spotlight(NSMetadataQuery)는 색인이 꺼진 맥에서 아무것도 못 찾아(실측: mdfind 0건) 폴더를 직접 본다.
/// 스크린샷 여부는 macOS가 붙이는 확장 속성 `kMDItemIsScreenCapture`로 가린다 — 폴더에 다른 파일을
/// 옮겨 넣어도 먹이가 쏟아지지 않는다. 찍은 영역(`kMDItemScreenCaptureGlobalRect`)도 함께 넘긴다.
final class ScreenshotWatcher {
    /// 새 스크린샷. 찍은 영역은 전역 좌표(주 화면 왼쪽 위 원점, 포인트). 메인 스레드에서 부른다.
    var onCapture: ((CGRect?) -> Void)?
    /// 폴더를 열 수 없음(바탕화면 접근 거절 등). 메인 스레드에서 부른다.
    var onDenied: (() -> Void)?

    private let queue = DispatchQueue(label: "aquarium.screenshots")
    private var source: DispatchSourceFileSystemObject?
    private var folder: URL?
    private var known: Set<String> = []
    private var lastFire = Date.distantPast
    private var recheck: DispatchSourceTimer?
    /// 연속 촬영(⌘⇧3 연타)에 먹이가 폭포처럼 쏟아지지 않게.
    private static let cooldown: TimeInterval = 10

    func start() {
        queue.async { [weak self] in
            self?.watch(Self.screenshotFolder())
            // 저장 위치는 실행 중에도 바뀔 수 있다(⌘⇧5 옵션) — 가끔 다시 읽는다.
            let timer = DispatchSource.makeTimerSource(queue: self?.queue)
            timer.schedule(deadline: .now() + 60, repeating: 60)
            timer.setEventHandler { [weak self] in
                let current = Self.screenshotFolder()
                if current != self?.folder { self?.watch(current) }
            }
            timer.resume()
            self?.recheck = timer
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.recheck?.cancel()
            self?.recheck = nil
            self?.source?.cancel()
            self?.source = nil
            self?.folder = nil
        }
    }

    /// `com.apple.screencapture location` → 없거나 폴더가 사라졌으면 바탕화면(macOS도 그렇게 저장한다).
    /// Probe 중에는 AQUARIUM_SCREENSHOT_DIR로 바꿀 수 있다(실제 폴더를 건드리지 않는 테스트용).
    static func screenshotFolder() -> URL {
        if Probe.enabled, let dir = ProcessInfo.processInfo.environment["AQUARIUM_SCREENSHOT_DIR"] {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        guard let raw = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
              !raw.isEmpty else { return desktop }
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? url : desktop
    }

    // MARK: - 감시 (queue 위에서만)

    private func watch(_ url: URL) {
        source?.cancel()
        source = nil
        folder = url
        // 바탕화면이면 여기서 macOS가 폴더 접근 권한을 묻는다(처음 한 번). 답할 때까지 이 큐가 기다린다.
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0, let names = try? listing(url) else {
            if fd >= 0 { close(fd) }
            folder = nil
            DispatchQueue.main.async { [weak self] in self?.onDenied?() }
            return
        }
        known = names
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)
        source.setEventHandler { [weak self] in self?.scan() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func listing(_ url: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") })
    }

    private func scan() {
        guard let folder, let names = try? listing(folder) else { return }
        let added = names.subtracting(known)
        known = names
        // 저장 중인 임시 파일(.으로 시작)은 listing에서 빠지고, 이름이 바뀌어 나타날 때 잡힌다.
        for name in added {
            let path = folder.appendingPathComponent(name).path
            guard Self.isScreenCapture(path) else { continue }
            guard Date().timeIntervalSince(lastFire) >= Self.cooldown else { return }
            lastFire = Date()
            let rect = Self.captureRect(path)
            DispatchQueue.main.async { [weak self] in self?.onCapture?(rect) }
            return
        }
    }

    private static func isScreenCapture(_ path: String) -> Bool {
        (attribute("kMDItemIsScreenCapture", of: path) as? Bool) ?? false
    }

    /// [x, y, 너비, 높이] — 전역 좌표(주 화면 왼쪽 위 원점, 포인트).
    private static func captureRect(_ path: String) -> CGRect? {
        guard let v = attribute("kMDItemScreenCaptureGlobalRect", of: path) as? [Double], v.count == 4 else { return nil }
        return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }

    /// `com.apple.metadata:` 확장 속성은 바이너리 plist로 들어 있다.
    private static func attribute(_ name: String, of path: String) -> Any? {
        let key = "com.apple.metadata:" + name
        let size = getxattr(path, key, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(path, key, $0.baseAddress, size, 0, 0) }
        guard read == size else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil)
    }
}
