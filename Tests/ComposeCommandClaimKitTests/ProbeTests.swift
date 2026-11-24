@testable import ComposeCommandClaimKit
import Testing

/// Answers a model gives. Correct ones must never be called wrong or flagged; wrong ones must be caught with the
/// slip that explains them.
@Suite("Probes")
struct ProbeTests {
    static let web = yaml("services:\n  web:\n    image: node:20\n    command: npm run dev")
    static let shell = yaml("services:\n  web:\n    image: node:20\n    command: [\"sh\", \"-c\", \"cd /app && npm start\"]")
    static let tini = dockerfile("FROM node:20\nENTRYPOINT [\"docker-entrypoint.sh\"]\nCMD [\"node\", \"server.js\"]")
        + yaml("services:\n  app:\n    build: .\n    entrypoint: [\"/sbin/tini\", \"--\"]\n    command: [\"node\", \"server.js\"]")

    static let correct: [String] = [
        shell + "Compose doesn't run `command` through a shell, so the list starts one.",
        shell + "`web` runs `cd /app && npm start` inside `sh -c`.",
        "Unlike a Dockerfile's shell-form `CMD`, a compose `command` string is not run through `/bin/sh -c`.",
        "In compose, `&&` won't work in a plain `command` string without `sh -c`.",
        "Compose stops reading the string at `&&` and drops the rest.",
        "In compose, everything after `&&` is dropped, so `npm start` never runs.",
        tini + "Setting `entrypoint` drops the image's `CMD`, so the file repeats it in `command`.",
        tini + "`app` runs `/sbin/tini -- node server.js`.",
        tini + "`app` runs `node server.js` under tini.",
        "In compose, an empty `entrypoint: \"\"` keeps the image's `CMD`.",
        web + "`docker compose run web npm test` runs `npm test` instead of `npm run dev`.",
        web + "With `--entrypoint`, `docker compose run` drops the service's `command`.",
        "Compose substitutes `$TAG` from your shell or `.env` when it reads the file.",
        yaml("apiVersion: v1\nkind: Pod") + "Here `command` replaces the image's `ENTRYPOINT`.",
        "In Kubernetes, `command` overrides the entrypoint, but in compose `command` replaces only `CMD`.",
        "A string `test` in a healthcheck runs through a shell, but compose's `command` does not.",
        web + "`web` runs `npm run dev`.",
        web + "If you need shell features, wrap the command in `sh -c`.",
        web + "You might expect `cd /app && npm start` to run both, but compose stops at `&&`.",
        web + "Run `docker compose up` to start it.",
        "In compose, `command:` is passed to the image's `ENTRYPOINT` as arguments.",
        "In compose, an empty `command: []` falls back to the image's CMD.",
        web + "\(fence)env\nGREETING=hi\n\(fence)\n`$GREETING` becomes `hi`.",
        web + "`web` runs `npm start` and `db` runs `postgres`.",
        "Compose doesn't wrap `command` in `/bin/sh -c`; it splits the string into words.",
        "`docker run --entrypoint` also drops the image's CMD in compose files.",
        yaml("services:\n  worker:\n    image: alpine\n    command: [\"sh\", \"-c\", \"echo ready\"]")
            + "`worker` runs `sh -c 'echo ready'`.",
        dockerfile("FROM scratch\nENTRYPOINT [\"/entry.sh\"]\nCMD [\"serve\"]") + yaml("services:\n  web:\n    build: .")
            + "The container runs `/entry.sh serve`."
    ]

    static let nearMisses: [String] = [
        yaml("services:\n  web:\n    image: a\n    environment:\n      PORT: \"3000\"")
            + "`$PORT` is set in the container by `environment:`.",
        "In compose, `$PORT` isn't set in your shell.",
        "In compose, `command` behaves differently than in a shell.",
        "In compose, `&&` literally ends the command string.",
        "Compose runs it through go-shellwords, not a shell.",
        "Compose splits the `command` string the way a shell would, but it never runs one.",
        "In compose, `command` overrides the image's `CMD`.",
        "Setting `entrypoint` overrides the image's `ENTRYPOINT` and also resets its `CMD` in compose.",
        "The `$PORT` variable is read from `.env` when compose parses the file.",
        "In compose, unlike `entrypoint`, `command` is appended to the image's `ENTRYPOINT`.",
        "`docker compose run web bash` runs `bash` instead of the service's command."
    ]

    @Test(arguments: correct + nearMisses)
    func correctAnswersStayQuiet(_ answer: String) {
        let report = check(answer)
        #expect(report.flagged.isEmpty, "\(report.findings.map(\.explanation))")
    }

    @Test func fileInTheQuestion() {
        let question = "Why does only the first part run?\n"
            + yaml("services:\n  web:\n    image: node:20\n    command: npm install && npm start")
        let report = check("Your `command` stops at `&&`, so `web` only runs `npm install`.", context: question)
        #expect(report.flagged.isEmpty && report.findings.count == 2, "\(report.findings.map(\.outcome))")
        let wrong = check("`web` runs `npm install && npm start`.", context: question)
        #expect(wrong.findings.first?.slip == .stringRunsInShell)
    }

    static let wrong: [(String, CommandFinding.Slip)] = [
        ("Compose runs `command` through `/bin/sh -c`.", .stringRunsInShell),
        ("In compose, `&&` is passed to `cd` as a literal argument.", .operatorBecomesArgument),
        ("Compose: nothing after `&&` is dropped.", .operatorBecomesArgument),
        ("In compose, `$GREETING` is read from the `environment:` block when the container starts.",
         .variableReadInContainer),
        ("Setting `entrypoint` in compose keeps the image's `CMD`.", .entrypointKeepsImageCmd),
        ("In compose, an empty `entrypoint: \"\"` drops the image's `CMD` too.", .emptyEntrypointDropsCmd),
        ("In compose, `command` replaces the image's `ENTRYPOINT`.", .commandReplacesEntrypoint),
        ("`docker compose run` appends its arguments to the service's command.", .runAppendsToCommand),
        ("`docker compose run --entrypoint sh web` still runs the service's command.", .runEntrypointKeepsCommand),
        ("In compose, an empty `command: []` runs nothing.", .emptyCommandClears),
        (web + "`docker compose run web npm test` runs `npm run dev npm test`.", .runAppendsToCommand),
        (yaml("services:\n  web:\n    image: node:20\n    command: [\"npm run dev\"]") + "`web` runs `npm run dev`.",
         .listItemSplit)
    ]

    @Test(arguments: wrong)
    func wrongAnswersCaught(_ row: (String, CommandFinding.Slip)) {
        let found = sentenceFindings(check(row.0))
        #expect(found.contains { $0.slip == row.1 }, "\(found.map(\.outcome))")
    }
}
