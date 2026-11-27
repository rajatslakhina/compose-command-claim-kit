@testable import ComposeCommandClaimKit
import Testing

/// Correct answers about a healthcheck's `test:` that 1.0.1 read as statements about `command:` (found while wiring
/// HealthcheckClaimKit into ai-chat-app): each must stay quiet, and the same words about a `command:` must not.
@Suite("Healthcheck answers")
struct HealthcheckProbeTests {
    static let broken = "My web container never turns healthy.\n" + yaml("""
    services:
      web:
        image: nginx:1.27
        healthcheck:
          test: ["CMD", "curl", "-f", "http://localhost", "||", "exit", "1"]
    """)

    static let postgres = "Why does my postgres healthcheck fail?\n" + yaml("""
    services:
      db:
        image: postgres:18
        environment:
          POSTGRES_USER: app
        healthcheck:
          test: ["CMD-SHELL", "pg_isready -U $POSTGRES_USER -d app"]
    """)

    static let quiet: [(answer: String, context: String)] = [
        ("The exec form runs `curl` directly, so the `||` reached it as an argument.", broken),
        ("`$POSTGRES_USER` becomes `$$POSTGRES_USER` so that it is resolved inside the container.", postgres),
        ("`$POSTGRES_USER` becomes `$$POSTGRES_USER` so it is resolved inside the container.", postgres),
        ("With `test: [\"CMD\", ...]` the `||` is passed to `curl` as an argument.", broken)
    ]

    @Test(arguments: quiet.indices)
    func staysQuiet(_ index: Int) {
        let row = Self.quiet[index]
        let report = check(row.answer, context: row.context)
        #expect(report.flagged.isEmpty, "\(index): \(report.findings.map(\.explanation))")
    }

    @Test func scope() {
        let sentence = "the `&&` is passed to `npm` as an argument."
        #expect(!CommandClaimReader.aboutHealthcheck(.stringRunsInShell, service: "web", sentence: sentence,
                                                     scene: CommandScene()))
        #expect(!CommandClaimReader.aboutHealthcheck(.operatorPassedAsArgument, service: nil, sentence: sentence,
                                                     scene: CommandScene()))
        #expect(CommandClaimReader.aboutHealthcheck(.operatorPassedAsArgument, service: nil,
                                                    sentence: "In the healthcheck, " + sentence, scene: CommandScene()))
    }
}
