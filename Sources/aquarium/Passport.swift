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
        if let p = fish.personality { fish.personality = min(max(0, p), Personality.allCases.count - 1) }

        // 속도: 종별 범위 합집합이 0.08...0.7이고 아기가 0.2...0.45다. 정상값을
        // 절대 건드리지 않도록 넉넉하게 자른다. 비유한값은 0이 아니라 종의
        // 하한으로 — 속도 0인 물고기는 영원히 한 자리에 멈춰 선다.
        // (species 클램프 뒤여야 한다. allSpecies[fish.species]를 읽는다.)
        fish.speed = fish.speed.isFinite
            ? min(max(0.05, fish.speed), 1.0)
            : allSpecies[fish.species].speed.lowerBound

        // 성장 잔여: spawnBaby가 심는 값은 30~55초뿐이다.
        if let g = fish.growRemaining {
            fish.growRemaining = g.isFinite ? min(max(0, g), 300) : nil
        }

        // 출생 시각: 도감이 Int((now - bornAt) / 86400)을 만든다(World.swift).
        // isFinite만으로는 못 막는다 — 1e308 같은 '멀쩡한' 유한값도 몫이 Int
        // 범위를 넘겨 그 자리에서 트랩이다. 범위를 벗어나면 nil로 떨궈
        // makeFish가 tankBornAt으로 대체하게 둔다(기존 동작).
        let nowEpoch = Date().timeIntervalSince1970
        if let b = fish.bornAt, !(b.isFinite && b >= 0 && b <= nowEpoch + 86_400) {
            fish.bornAt = nil
        }

        if let id = fish.id, id.count > 64 { fish.id = String(id.prefix(64)) }

        // 이름·여권은 상태줄과 도감에 그대로 찍힌다(이스케이프 없음). 코드가
        // 반공개 채널을 타고 오므로 ESC 시퀀스가 섞이면 화면이 지워진다.
        // origin은 발신자 머신의 AQUARIUM_TANKNAME에서 온다.
        fish.name = sanitized(fish.name, max: 20)
        if let origin = fish.origin {
            // suffix — origin.last가 표시되고 release가 뒤에 append한다.
            let cleaned = origin.compactMap { sanitized($0, max: 20) }
            fish.origin = cleaned.isEmpty ? nil : Array(cleaned.suffix(20))
        }
        // color는 UInt8이라 0...255가 전부 유효한 ANSI 인덱스 — 클램프할 게 없다.
        // color2는 FishState에 없다(Fish 전용 표시 필드).
        return fish
    }

    /// 터미널 제어문자(C0 + DEL + C1)를 걷어내고 길이를 자른다.
    /// 빈 문자열이 되면 nil을 돌려 makeFish가 새 이름을 붙이게 한다.
    ///
    /// CharacterSet.controlCharacters를 쓰지 않는다 — 그쪽은 Cf(포맷)까지
    /// 걸러서 ZWJ로 이어붙인 이모지 이름이 깨진다. 터미널이 실제로
    /// 실행해버리는 건 C0/C1뿐이다.
    private static func sanitized(_ s: String?, max: Int) -> String? {
        guard let s else { return nil }
        var scalars = String.UnicodeScalarView()
        for u in s.unicodeScalars
        where !(u.value < 0x20 || u.value == 0x7F || (0x80...0x9F).contains(u.value)) {
            scalars.append(u)
        }
        let cleaned = String(String(scalars).prefix(max))
        return cleaned.isEmpty ? nil : cleaned
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
        let token = prefix + String(code.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(prefix.count))
        guard AdoptInbox.deposit(token) else {
            // 코드는 멀쩡한데 큐에 못 넣었다. exit 1(= 잘못된 코드)을 쓰면
            // 자동화(Slack poller 등)가 ⚠️를 붙이고 영영 끝내버린다 — 이건
            // 재시도해야 하는 실패다. 75는 sysexits.h의 EX_TEMPFAIL.
            print(L10n.adoptQueueFailed)
            exit(75)
        }
        print(L10n.adoptQueued(fish.name ?? "?"))
    }
}
