@testable import ComposeCommandClaimKit
import Testing

/// Correct answers traced to a flag after 1.0.0: each must stay quiet.
@Suite("Follow-up probes")
struct FollowUpProbeTests {
    static let question = "My web service installs but the server never starts. Why?\n"
        + yaml("services:\n  web:\n    image: node:20-alpine\n    command: npm install && npm start")

    static let quiet: [(answer: String, context: String)] = [
        ("Use `command: bash -c \"npm install && npm start\"`, which runs `npm install && npm start` in bash.", question),
        ("In the Dockerfile, the shell-form `CMD` runs `npm install && npm start` through `/bin/sh -c`.", question),
        ("Setting `entrypoint` drops the image's `CMD` while your `command` is still appended.", question),
        (yaml("services:\n  web:\n    image: node:20\n    environment:\n      PORT: \"3000\"\n"
              + "    command: node server.js --port ${PORT:-3000}"), "")
    ]

    @Test(arguments: quiet.indices)
    func staysQuiet(_ index: Int) {
        let row = Self.quiet[index]
        let report = check(row.answer, context: row.context)
        #expect(report.flagged.isEmpty, "\(index): \(report.findings.map(\.explanation))")
    }
}
