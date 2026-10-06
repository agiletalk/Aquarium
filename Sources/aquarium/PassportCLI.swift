import AquariumCore
import Foundation

extension Passport {
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
