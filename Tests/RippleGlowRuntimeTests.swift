import Foundation

@main
enum RippleGlowRuntimeTests {
    static func main() {
        if let error = RippleGlowRuntimeValidator.validationError() {
            fputs("Ripple Glow runtime test failed: \(error)\n", stderr)
            exit(1)
        }
        print("QuotaView orb runtime test passed: fixed Ripple Glow Metal pipeline is available.")
    }
}
