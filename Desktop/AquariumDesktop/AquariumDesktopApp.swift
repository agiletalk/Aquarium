import AppKit
import SwiftUI

@main
struct AquariumDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // TODO(Step 4): 켜기/끄기·로그인 실행·먹이·조명·계절·음악·언어.
        MenuBarExtra("Aquarium", systemImage: "fish") {
            DisplayMenu(wallpaper: appDelegate.wallpaper)
            Divider()
            Button("종료") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

/// 모니터가 둘 이상일 때만 보이는 "표시할 모니터" 선택.
private struct DisplayMenu: View {
    @ObservedObject var wallpaper: WallpaperController

    var body: some View {
        if wallpaper.displays.count > 1 {
            Picker("표시할 모니터", selection: Binding(
                get: { wallpaper.selectedDisplayID ?? wallpaper.displays.first?.id ?? "" },
                set: { wallpaper.selectedDisplayID = $0 }
            )) {
                ForEach(wallpaper.displays) { Text($0.name).tag($0.id) }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SwiftUI 메뉴가 body를 그릴 때 이미 있어야 해서 지연 생성하지 않는다.
    let wallpaper = WallpaperController()

    func applicationWillTerminate(_ notification: Notification) {
        wallpaper.save()
    }
}
