import AppKit
import AquariumCore
import ServiceManagement
import SwiftUI

@main
struct AquariumDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Aquarium", systemImage: "fish") {
            AquariumMenu(wallpaper: appDelegate.wallpaper)
        }
    }
}

/// 메뉴바 메뉴. 터미널의 키 조작 중 화면 없이 되는 것만 옮겼다 —
/// 도감·편지함·업적·집중 모드는 화면이 필요해 v0.2.
private struct AquariumMenu: View {
    @ObservedObject var wallpaper: WallpaperController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle(t("수족관 켜기", "Show Aquarium"), isOn: $wallpaper.enabled)

        Divider()
        Group {
            Button(t("먹이 주기", "Feed")) { wallpaper.feed() }
            Button(t("생먹이 주기", "Feed Live Shrimp")) { wallpaper.feedLive() }
            Picker(t("조명", "Lighting"), selection: Binding(
                get: { wallpaper.lighting }, set: { wallpaper.setLighting($0) })) {
                Text(t("자동", "Auto")).tag(Lighting.auto)
                Text(t("낮", "Day")).tag(Lighting.day)
                Text(t("밤", "Night")).tag(Lighting.night)
            }
            Picker(t("계절", "Season"), selection: Binding(
                get: { wallpaper.season }, set: { wallpaper.setSeason($0) })) {
                Text(t("자동", "Auto")).tag(Season.auto)
                Text(t("여름", "Summer")).tag(Season.summer)
                Text(t("끄기", "Off")).tag(Season.off)
            }
            Toggle(t("음악", "Music"), isOn: Binding(
                get: { wallpaper.musicPlaying }, set: { _ in wallpaper.toggleMusic() }))
        }
        .disabled(!wallpaper.enabled)

        Divider()
        Group {
            if wallpaper.focusing {
                Button(t("집중 취소", "Cancel Focus")) { wallpaper.cancelFocus() }
            } else {
                Menu(t("집중 시작", "Start Focus")) {
                    ForEach([25, 50], id: \.self) { minutes in
                        Button(t("\(minutes)분", "\(minutes) min")) { wallpaper.startFocus(minutes: minutes) }
                    }
                }
            }
            Picker(t("정원", "Capacity"), selection: Binding(
                get: { wallpaper.fishCap }, set: { wallpaper.setFishCap($0) })) {
                Text(t("작게 (40)", "Small (40)")).tag(40)
                Text(t("보통 (80)", "Medium (80)")).tag(80)
                Text(t("크게 (120)", "Large (120)")).tag(120)
            }
        }
        .disabled(!wallpaper.enabled)

        Divider()
        if wallpaper.displays.count > 1 {
            Picker(t("표시할 모니터", "Display"), selection: Binding(
                get: { wallpaper.selectedDisplayID ?? wallpaper.displays.first?.id ?? "" },
                set: { wallpaper.selectedDisplayID = $0 })) {
                ForEach(wallpaper.displays) { Text($0.name).tag($0.id) }
            }
        }
        if wallpaper.gpuAvailable {
            Toggle(t("GPU 렌더링", "GPU Rendering"), isOn: Binding(
                get: { wallpaper.gpuRendering }, set: { wallpaper.setGPURendering($0) }))
        }
        Picker(t("언어", "Language"), selection: Binding(
            get: { L10n.isKorean }, set: { wallpaper.setKorean($0) })) {
            Text("한국어").tag(true)
            Text("English").tag(false)
        }
        Toggle(t("로그인 시 실행", "Launch at Login"), isOn: Binding(
            get: { launchAtLogin },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("Aquarium: 로그인 항목 변경 실패 — \(error.localizedDescription)")
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }))

        Divider()
        Button(t("종료", "Quit")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SwiftUI 메뉴가 body를 그릴 때 이미 있어야 해서 지연 생성하지 않는다.
    let wallpaper = WallpaperController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        TerminalImport.offerIfNeeded()
        wallpaper.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaper.save()
    }
}
