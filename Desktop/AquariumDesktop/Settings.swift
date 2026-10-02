import AquariumCore
import Foundation

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
