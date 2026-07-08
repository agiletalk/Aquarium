import Foundation

/// 후원 링크 설정 + `aquarium --sponsor` CLI.
enum Support {
    static let url = "https://ko-fi.com/agiletalk"
    static let display = "ko-fi.com/agiletalk"

    /// macOS 기본 브라우저로 후원 페이지 열기
    static func openInBrowser() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url]
        try? process.run()
    }

    static func printCLI() {
        print(ANSI.fg(219) + L10n.sponsorTitle + ANSI.reset)
        print(L10n.sponsorThanks1)
        print(L10n.sponsorThanks2)
        print("")
        print(ANSI.fg(45) + display + ANSI.reset)
    }
}
