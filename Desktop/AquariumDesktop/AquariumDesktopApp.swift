import AppKit
import SwiftUI

@main
struct AquariumDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // TODO(Step 4): 켜기/끄기·로그인 실행·먹이·조명·계절·음악. 스파이크는 종료만.
        MenuBarExtra("Aquarium", systemImage: "fish") {
            Button("종료") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var wallpaper: WallpaperController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        wallpaper = WallpaperController()
    }
}
