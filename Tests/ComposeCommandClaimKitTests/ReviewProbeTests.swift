@testable import ComposeCommandClaimKit
import Testing

/// Correct answers found by reading the reader code before the first tag: each must stay quiet.
@Suite("Review probes")
struct ReviewProbeTests {
    static let broken = yaml("services:\n  web:\n    image: node:20\n    command: npm install && npm start")
    static let fixed = yaml("services:\n  web:\n    image: node:20\n    command: [\"sh\", \"-c\", \"npm install && npm start\"]")

    static let quiet: [(answer: String, context: String)] = [
        ("No, Compose doesn't run `command` through a shell.", ""),
        ("Because `command` isn't run in a shell, `&&` has no special meaning in compose.", ""),
        ("Compose doesn't run `command` through a shell and doesn't expand `~`.", ""),
        ("With no shell involved, everything after `&&` is dropped in compose.", ""),
        ("Your file:\n" + broken + "\nCompose stops at `&&`. The fix:\n" + fixed
            + "\nNow `web` runs `npm install && npm start` in `sh -c`.", ""),
        ("Here is your file again:\n" + broken + "\nCompose stops reading at `&&`.", broken),
        (yaml("services:\n  cache:\n    image: redis:7\n    environment:\n      REDIS_PASSWORD: ${REDIS_PASSWORD}\n"
              + "    command: redis-server --requirepass ${REDIS_PASSWORD}")
            + "Compose fills `${REDIS_PASSWORD}` from your shell or `.env` when it reads the file.", ""),
        ("In compose, with the list form, the whole script, `&&` included, is passed to `sh` as an argument.", ""),
        (fixed + "`web` runs `sh -c npm install && npm start`.", ""),
        ("Here `command` replaces the image's `ENTRYPOINT`.",
         "How do I move this to compose?\n" + yaml("apiVersion: v1\nkind: Pod\nspec:\n  containers: []")),
        ("Compose and Kubernetes differ. In a Kubernetes pod, it is different. There, `command` replaces the image's "
            + "`ENTRYPOINT`.", "")
    ]

    @Test(arguments: quiet.indices)
    func staysQuiet(_ index: Int) {
        let row = Self.quiet[index]
        let report = check(row.answer, context: row.context)
        #expect(report.flagged.isEmpty, "\(index): \(report.findings.map(\.explanation))")
    }
}
