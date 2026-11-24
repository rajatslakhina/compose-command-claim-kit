@testable import ComposeCommandClaimKit
import Testing

@Suite("Judging claims")
struct EvaluatorTests {
    let checker = CommandClaimChecker()

    func finding(_ answer: String, context: String = "") -> CommandFinding? {
        sentenceFindings(check(answer, context: context)).first
    }

    @Test func runsWithoutProjectOrService() {
        #expect(finding("Compose: it runs `x`.")?.outcome == .unchecked("the conversation shows no compose file"))
        let two = yaml("services:\n  web:\n    image: a\n    command: x\n  api:\n    image: b\n    command: y")
        #expect(finding(two + "It runs `x`.")?.outcome == .unchecked("the sentence names no service of the compose file"))
    }

    @Test func runsMatches() {
        let file = yaml("services:\n  web:\n    image: node:20\n    command: npm run dev")
        #expect(finding(file + "`web` runs `npm run dev`.")?.outcome == .exact)
        #expect(finding(file + "`web` runs `x npm run dev`.")?.outcome
            == .unchecked("the image's ENTRYPOINT, which the conversation does not show, comes first"))
        #expect(finding(file + "`web` runs `npm`.")?.outcome.isUnchecked == true)
    }

    @Test func runsUnknownWords() {
        let file = yaml("""
        services:
          web:
            image: alpine
            environment:
              GREETING: hello
            command: echo $GREETING
          other:
            image: alpine
            command: echo $TAG
          refused:
            image: alpine
            command: echo (a)
        """)
        let caveat = finding(file + "`web` runs `echo hello`.")
        #expect(caveat?.outcome == .caveat(.variableFromShell))
        #expect(caveat?.actual?.contains("With nothing set, it runs") == true)
        #expect(finding(file + "`web` runs `echo bye`.")?.outcome.isUnchecked == true)
        #expect(finding(file + "`other` runs `echo 1`.")?.outcome.isUnchecked == true)
        #expect(finding(file + "`refused` runs `echo (a)`.")?.outcome.isUnchecked == true)
    }

    @Test func entrypointPrefix() {
        let answer = dockerfile("FROM scratch\nENTRYPOINT [\"python\", \"manage.py\"]")
            + yaml("services:\n  app:\n    build: .\n    command: runserver")
        let found = finding(answer + "`app` runs `runserver`.")
        #expect(found?.outcome == .caveat(.entrypointPrefix))
        #expect(found?.actual?.contains("`python manage.py runserver`") == true)
        #expect(finding(answer + "`app` runs `python manage.py runserver`.")?.outcome == .exact)
    }

    @Test func runsSlips() {
        let base = "services:\n  web:\n    build: .\n"
        let cases: [(String, String, String, CommandFinding.Slip)] = [
            ("FROM scratch", base + "    command: cd /app && npm start", "cd /app && npm start", .stringRunsInShell),
            ("FROM scratch", base + "    entrypoint: cd /app && npm start", "cd /app && npm start", .stringRunsInShell),
            ("FROM scratch", base + "    command: [\"npm run dev\"]", "npm run dev", .listItemSplit),
            ("FROM scratch\nCMD [\"node\", \"app.js\"]", base + "    entrypoint: [\"tini\", \"--\"]",
             "tini -- node app.js", .entrypointKeepsImageCmd),
            ("FROM scratch\nENTRYPOINT exec /run", base + "    command: --verbose", "exec /run --verbose",
             .shellEntrypointTakesCommand),
            ("FROM scratch\nENTRYPOINT exec /run", base + "    command: --verbose", "--verbose",
             .commandReplacesEntrypoint),
            ("FROM scratch", base + "    entrypoint: [\"sh\", \"-c\"]\n    command: echo ready", "echo ready",
             .scriptTakesFollowingWords),
            ("FROM scratch", base + "    environment:\n      HOME: /root\n    command: echo $$HOME", "echo /root",
             .dollarDollarExpanded)
        ]
        for (image, compose, stated, slip) in cases {
            let found = finding(dockerfile(image) + yaml(compose) + "`web` runs `\(stated)`.")
            #expect(found?.slip == slip, "\(compose)")
            #expect(found?.actual?.hasPrefix("`web` runs ") == true)
        }
        let known = dockerfile("FROM scratch") + "\(fence)env\nGREETING=hi\n\(fence)\n"
            + yaml(base + "    environment:\n      GREETING: hello\n    command: echo $GREETING")
        #expect(finding(known + "`web` runs `echo hello`.")?.slip == .variableReadInContainer)
        #expect(finding(known + "`web` runs `echo x`.")?.outcome.isUnchecked == true)
    }

    @Test func runLineSlips() {
        let file = yaml("services:\n  web:\n    image: node:20\n    command: npm run dev")
        let appended = finding(file + "`docker compose run web npm test` runs `npm run dev npm test`.")
        #expect(appended?.slip == .runAppendsToCommand)
        #expect(appended?.actual?.hasPrefix("`docker compose run web npm test` runs") == true)
        #expect(finding(file + "`docker compose run --entrypoint /bin/sh web` runs `/bin/sh npm run dev`.")?.slip
            == .runEntrypointKeepsCommand)
        #expect(finding(file + "`docker compose run --entrypoint /bin/sh web` runs `/bin/sh`.")?.outcome == .exact)
        #expect(finding(file + "`docker compose run --entrypoint= web` runs `x`.")?.outcome.isUnchecked == true)
        #expect(finding(file + "`docker compose run --entrypoint /bin/sh web -c ls` runs `x`.")?.outcome.isUnchecked
            == true)
        #expect(finding(file + "`docker compose run web` runs `npm run dev`.")?.outcome == .exact)
        let none = yaml("services:\n  web:\n    image: node:20")
        #expect(finding(none + "`docker compose run web npm test` runs `npm test`.")?.outcome == .exact)
    }

    @Test func variables() {
        let file = """
        services:
          web:
            image: alpine
            environment:
              GREETING: hello
            command: echo $GREETING
          shell:
            image: alpine
            environment:
              NAME: box
            command: ["sh", "-c", "echo $$NAME"]
          plain:
            image: alpine
            environment:
              NAME: box
            entrypoint: ["echo"]
            command: ["$$NAME"]
          unseen:
            image: alpine
            command: echo $$NAME
          refused:
            image: alpine
            command: echo $$NAME (a)
        """
        let answer = yaml(file)
        #expect(finding(answer + "`$GREETING` becomes `hello`.")?.outcome == .caveat(.variableFromShell))
        #expect(finding(answer + "`$GREETING` becomes `x`.")?.outcome.isUnchecked == true)
        let env = "\(fence)env\nGREETING=hi\n\(fence)\n"
        #expect(finding(answer + env + "`$GREETING` becomes `hi`.")?.outcome == .exact)
        #expect(finding(answer + env + "`$GREETING` becomes `hello`.")?.slip == .variableReadInContainer)
        #expect(finding(answer + env + "`$GREETING` becomes `x`.")?.outcome.isUnchecked == true)
        let gone = "\(fence)env\nGREETING=\n\(fence)\n"
        #expect(finding(answer + gone + "In `web`, `${GREETING:?unset}` becomes `x`.")?.outcome.isUnchecked == true)
        #expect(finding(answer + "In `shell`, `$$NAME` becomes `box`.")?.outcome == .exact)
        #expect(finding(answer + "In `shell`, `$$NAME` becomes `x`.")?.outcome.isUnchecked == true)
        #expect(finding(answer + "In `plain`, `$$NAME` becomes `$NAME`.")?.outcome == .exact)
        #expect(finding(answer + "In `plain`, `$$NAME` becomes `box`.")?.slip == .dollarDollarExpanded)
        #expect(finding(answer + "In `unseen`, `$$NAME` becomes `box`.")?.outcome
            == .unchecked("the image's ENTRYPOINT, which the conversation does not show, may be a shell"))
        #expect(finding(answer + "In `refused`, `$$NAME` becomes `box`.")?.outcome.isUnchecked == true)
    }

    @Test func rules() {
        let file = yaml("""
        services:
          shell:
            image: alpine
            command: ["sh", "-c", "echo $$HOME"]
          plain:
            image: alpine
            entrypoint: ["echo"]
            command: ["$$TAG"]
          unseen:
            image: alpine
            command: echo $$X
        """)
        #expect(finding(file + "In `shell`, `$$HOME` is expanded in the container.")?.outcome == .exact)
        #expect(finding(file + "In `plain`, `$$TAG` is expanded in the container.")?.slip == .dollarDollarExpanded)
        #expect(finding(file + "In `unseen`, `$$X` is expanded in the container.")?.outcome.isUnchecked == true)
        #expect(finding("Compose fills `$$HOME` from your shell.")?.slip == .dollarDollarExpanded)
        #expect(finding("Compose fills `$HOME` from your shell.")?.outcome == .exact)
        #expect(finding("Compose: an empty `entrypoint: []` drops the image's `CMD`.")?.slip == .emptyEntrypointDropsCmd)
        #expect(finding("Compose: nothing after `&&` is dropped.")?.slip == .operatorBecomesArgument)
    }

    @Test(arguments: Rule.allCases)
    func everyRuleWording(_ rule: Rule) {
        let wrong = Wording.rule(rule, slip: rule.slip)
        #expect(!wrong.isEmpty)
        #expect(rule.slip.rawValue.isEmpty == false)
    }

    @Test func fileLines() {
        let answer = yaml("services:\n  web:\n    image: a\n    command: a && b")
        let scene = checker.scene(for: answer)
        let claim = CommandClaim(kind: .fileLine(service: "web", key: "command", line: 4, problem: .truncated),
                                 sentence: "command: a && b")
        #expect(checker.judge(claim, in: scene).slip == .stringRunsInShell)
        let missing = CommandClaim(kind: .fileLine(service: "web", key: "command", line: 9, problem: .truncated),
                                   sentence: "")
        #expect(checker.judge(missing, in: scene).outcome.isUnchecked)
        let other = CommandClaim(kind: .fileLine(service: "db", key: "command", line: 4, problem: .truncated),
                                 sentence: "")
        #expect(checker.judge(other, in: scene).outcome.isUnchecked)
    }
}

extension CommandFinding.Outcome {
    var isUnchecked: Bool {
        if case .unchecked = self { return true }
        return false
    }
}
