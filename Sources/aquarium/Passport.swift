import Foundation

/// 물고기 분양/입양: 물고기 한 마리를 base64url 코드로 직렬화해 사람 손(Slack 등)으로 주고받는다.
/// 서버 없이, 코드 문자열 하나가 물고기의 전부다.
enum Passport {
    static let prefix = "AQUA1."

    /// 현재 어항 주인 이름 (여권 도장용)
    static func tankName() -> String {
        let env = ProcessInfo.processInfo.environment
        if let name = env["AQUARIUM_TANKNAME"], !name.isEmpty { return name }
        if let user = env["USER"], !user.isEmpty { return user }
        return L10n.isKorean ? "어떤" : "someone"
    }

    static func encode(_ fish: FishState) -> String? {
        guard let data = try? JSONEncoder().encode(fish) else { return nil }
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return prefix + b64
    }

    static func decode(_ code: String) -> FishState? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        var b64 = String(trimmed.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              var fish = try? JSONDecoder().decode(FishState.self, from: data) else { return nil }
        // 손상되거나 조작된 코드 방어: 값 클램프
        fish.species = min(max(0, fish.species), allSpecies.count - 1)
        fish.eaten = min(max(0, fish.eaten), 99_999)
        if let m = fish.morph { fish.morph = min(max(0, m), rareMorphs.count) }
        if let name = fish.name, name.count > 20 { fish.name = String(name.prefix(20)) }
        return fish
    }

    // MARK: - CLI

    /// `aquarium --release <이름>`
    static func release(name: String) {
        guard let save = SaveStore.load(), !save.fish.isEmpty else {
            print(L10n.statusNoTank)
            return
        }
        let query = name.lowercased()
        guard var fish = save.fish.first(where: { ($0.name ?? "").lowercased() == query }) else {
            print(L10n.releaseNotFound(name))
            exit(1)
        }
        if fish.id == nil { fish.id = UUID().uuidString }
        var origin = fish.origin ?? []
        origin.append(tankName())
        fish.origin = origin

        guard let token = encode(fish) else {
            print(L10n.releaseFailed)
            exit(1)
        }
        // 어항이 실제로 떠나보내는 건 실행 중인 앱(또는 다음 실행)에 맡긴다 — 저장 충돌 방지
        ReleaseOutbox.request(fish.name ?? "")
        print(L10n.releasedCLI(fish.name ?? "?"))
        print("")
        print(token)
    }

    /// `aquarium --adopt <코드>`
    static func adopt(code: String) {
        guard let fish = decode(code) else {
            print(L10n.adoptInvalid)
            exit(1)
        }
        AdoptInbox.deposit(prefix + String(code.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(prefix.count)))
        print(L10n.adoptQueued(fish.name ?? "?"))
    }
}
