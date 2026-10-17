import Foundation

struct CodexSetupSnapshot: Equatable {
    let codexExecutableURL: URL?
}

/// Local onboarding and read-only executable discovery. No client configuration writes.
final class CodexSetupService {
    private let defaults: UserDefaults
    private let candidates: [URL]
    init(defaults: UserDefaults = .standard, candidates: [URL] = CodexExecutableLocator.candidateURLs()) {
        self.defaults = defaults
        self.candidates = candidates
    }
    var shouldPresentOnboarding: Bool { !defaults.bool(forKey: "setup.onboarding.completed") }
    func markOnboardingCompleted() { defaults.set(true, forKey: "setup.onboarding.completed") }
    func snapshot() -> CodexSetupSnapshot {
        CodexSetupSnapshot(codexExecutableURL: candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) })
    }
}
