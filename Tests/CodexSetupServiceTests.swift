import Foundation

@main
struct CodexSetupServiceTests {
    static func main() throws {
        let name = "CodexSetupTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let missing = CodexSetupService(defaults: defaults, candidates: [])
        precondition(missing.shouldPresentOnboarding)
        precondition(missing.snapshot().codexExecutableURL == nil)
        missing.markOnboardingCompleted()
        precondition(!missing.shouldPresentOnboarding)
        let reloaded = CodexSetupService(defaults: defaults, candidates: [URL(fileURLWithPath: "/usr/bin/true")])
        precondition(!reloaded.shouldPresentOnboarding)
        precondition(reloaded.snapshot().codexExecutableURL?.path == "/usr/bin/true")
        print("Codex setup tests: 5/5 passed (read-only discovery and onboarding)")
    }
}
