import AquariumCore
import Foundation
import Metal

/// UserDefaults에 남기는 앱 설정. 조명·계절은 어항의 속성이라 세이브에 들어간다.
enum Settings {
    private static let defaults = UserDefaults.standard

    /// 수족관 표시 여부 (메뉴의 켜기/끄기). 기본 켜짐.
    static var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    /// 상태줄·메뉴 언어. 기본 한국어 — GUI 앱에는 AQUARIUM_LANG 같은 환경 변수가 없다.
    static var korean: Bool {
        get { defaults.object(forKey: "korean") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "korean")
            L10n.isKorean = newValue
        }
    }

    /// GPU(Metal) 렌더링. 꺼져 있거나 Metal을 쓸 수 없으면 CPU(IOSurface) 렌더러.
    ///
    /// 기본값은 통합 메모리(Apple Silicon)일 때만 켬 — 측정(Release, 내장 Retina)에서 앱 CPU가
    /// 평균 3.2% → 1.85%로 줄고 메모리는 99 → 124MB. 외장 GPU를 12.5Hz로 깨우는 건
    /// 이득이 불분명해 Intel 맥은 CPU 렌더러로 둔다.
    static var gpuRendering: Bool {
        get { defaults.object(forKey: "gpuRendering") as? Bool ?? (MTLCreateSystemDefaultDevice()?.hasUnifiedMemory ?? false) }
        set { defaults.set(newValue, forKey: "gpuRendering") }
    }

    /// 화면 테마. 기본은 지금까지와 같은 딥 네이비.
    static var theme: Theme {
        get { defaults.string(forKey: "theme").flatMap(Theme.init(rawValue:)) ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: "theme") }
    }

    /// 정원 상한 (메뉴: 작게 40 / 보통 80 / 크게 120). 기본은 lounge 그대로 120.
    static var fishCap: Int {
        get { defaults.object(forKey: "fishCap") as? Int ?? 120 }
        set { defaults.set(newValue, forKey: "fishCap") }
    }
    static let fishCapChoices = [40, 80, 120]

    /// 첫 실행 때 터미널 어항 가져오기를 이미 물어봤는지.
    static var importAsked: Bool {
        get { defaults.bool(forKey: "importAsked") }
        set { defaults.set(newValue, forKey: "importAsked") }
    }
}

/// 메뉴 문구 (L10n과 같은 ko/en 쌍).
func t(_ ko: String, _ en: String) -> String { L10n.isKorean ? ko : en }
