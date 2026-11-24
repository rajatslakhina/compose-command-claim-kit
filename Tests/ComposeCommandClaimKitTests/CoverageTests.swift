@testable import ComposeCommandClaimKit
import DockerfileClaimKit
import EntrypointClaimKit
import Testing

/// The less common paths, each named for what it shows.
@Suite("Edges")
struct CoverageTests {
    @Test func yamlEdges() throws {
        #expect(try ComposeYAML.parse("a:") == .map([ComposeEntry(key: "a", value: .null, line: 1)]))
        #expect(try ComposeYAML.parse("list:\n  -\n    a: 1")["list"]?.items?.first?["a"] == .scalar("1"))
        #expect(throws: ComposeYAML.Unsupported.self) { try ComposeYAML.parse("  a: 1\nb: 2") }
        #expect(try ComposeYAML.parse("c: [\"sh\", \"-c\", \"echo \\\"hi, there\\\"\"]")["c"]?.items?.count == 3)
        #expect(try ComposeYAML.parse("m: {a:, b: 1}")["m"]?["a"] == .null)
        #expect(ComposeProject.looksLikeCompose("\nservices:\n  web: {}"))
    }

    @Test func sceneEdges() {
        let checker = CommandClaimChecker()
        let text = "\(fence)env\nA=1\n\nA=2\n\(fence)\n\(fence)sh\nexport B=1\nexport B=2\n\(fence)\n"
        #expect(checker.scene(for: text).variables == Variables(shell: ["B": "2"], dotEnv: ["A": "2"]))
        #expect(checker.scene(for: yaml("services:\n  - web")).projectNote == "the compose file has no `services:` mapping")
        #expect(checker.scene(for: yaml("services:\n  web:\n    image: a")).projectNote == nil)
        let earlier = checker.scene(for: yaml("services:\n  web: *x"))
        #expect(SceneReader.read(answer: "x", context: "", earlier: earlier).projectNote?.contains("an alias") == true)
    }

    @Test func readerEdges() {
        let checker = CommandClaimChecker()
        let file = yaml("services:\n  web:\n    image: node:20\n    command: npm run dev")
        #expect(checker.claims(in: file + "`web` starts and then runs `npm run dev`.").count == 1)
        #expect(checker.claims(in: file + "`web` runs the command `npm run dev`.").count == 1)
        #expect(checker.claims(in: file + "`web` runs instead `x`.").isEmpty)
        #expect(checker.claims(in: "With compose, `npm start` becomes `x`.").isEmpty)
        #expect(checker.claims(in: "In compose, setting `entrypoint` keeps the image's default command.").count == 1)
    }

    @Test func judgeEdges() {
        let none = check(dockerfile("FROM scratch") + yaml("services:\n  web:\n    build: .") + "`web` runs `x`.")
        #expect(none.findings.first?.outcome == .unchecked("it differs from what compose starts (nothing (the daemon "
            + "refuses with \"no command specified\")), and no known misreading explains it"))
        #expect(Wording.process(ContainerProcess(entrypoint: nil, command: nil)) == "the image's ENTRYPOINT and CMD")
        let refusedEntrypoint = yaml("services:\n  web:\n    image: a\n    entrypoint: echo (a)\n    command: x")
        #expect(sentenceFindings(check(refusedEntrypoint + "`web` runs `x`.")).first?.outcome
            == .unchecked("`docker compose` refuses this file: `web`'s `entrypoint:` has \(CommandWords.invalid)"))
        let refused = yaml("services:\n  web:\n    image: a\n    command: echo $$X (a)")
        #expect(sentenceFindings(check(refused + "In `web`, `$$X` is expanded in the container.")).first?.outcome
            == .unchecked("it depends on whether the command runs a shell, and the service's command is not known"))
        let gone = check(yaml("services:\n  web:\n    image: a\n    command: x") + "`web` runs `y`.").findings
        #expect(gone.first?.outcome.isUnchecked == true)
        let report = CommandReport(findings: [CommandFinding(claim: CommandClaim(kind: .runs(service: nil, stated: "x",
                                                                                              run: nil), sentence: ""),
                                                             outcome: .unchecked("why"))])
        #expect(report.summary == "1 claim checked, 0 hold, 1 unchecked")
    }

    @Test func runEdges() {
        let built = dockerfile("FROM scratch\nCMD [\"node\", \"app.js\"]")
            + yaml("services:\n  web:\n    build: .\n    command: npm run dev")
        let dropped = sentenceFindings(check(built + "`docker compose run --entrypoint /bin/sh web` runs `/bin/sh node app.js`."))
        #expect(dropped.first?.slip == .entrypointKeepsImageCmd)
        let kept = sentenceFindings(check(built + "`docker compose run --entrypoint /bin/sh web` runs `/bin/sh npm run dev`."))
        #expect(kept.first?.slip == .runEntrypointKeepsCommand)
        let plain = sentenceFindings(check(built + "`docker compose run web` runs `x`."))
        #expect(plain.first?.outcome.isUnchecked == true)
        #expect(Misreadings.commandInEffect(service("services:\n  web:\n    image: a")!, nil) == [])
    }

    @Test func fileEdges() {
        func problems(_ text: String) -> [FileProblem] {
            check(yaml(text)).findings.compactMap {
                if case let .fileLine(_, _, _, problem) = $0.claim.kind { return problem }
                return nil
            }
        }
        #expect(problems("services:\n  web:\n    image: a\n    entrypoint: sh -c echo hi") == [.splitScript])
        #expect(problems("services:\n  web:\n    image: a\n    entrypoint: \"'npm run dev'\"").isEmpty)
        #expect(problems("services:\n  web:\n    image: a\n    entrypoint: []\n    command: \"'a b'\"").isEmpty)
    }

    @Test func processEdges() throws {
        #expect(ContainerProcess.handsOn(["entrypoint"]) && !ContainerProcess.handsOn(["app"]))
        #expect(ContainerProcess.basename("/usr/bin/sh") == "sh" && ContainerProcess.basename("/") == "")
        #expect(try Interpolation.resolve("${GONE}", Variables(unset: ["GONE"])).value == "")
    }
}
