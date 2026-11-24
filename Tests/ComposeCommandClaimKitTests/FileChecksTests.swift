@testable import ComposeCommandClaimKit
import Testing

@Suite("File lines")
struct FileChecksTests {
    func problems(_ answer: String) -> [FileProblem] {
        check(answer).findings.compactMap {
            if case let .fileLine(_, _, _, problem) = $0.claim.kind { return problem }
            return nil
        }
    }

    @Test func eachProblem() {
        #expect(problems(yaml("services:\n  web:\n    image: a\n    command: cd /app && npm start")) == [.truncated])
        #expect(problems(yaml("services:\n  web:\n    image: a\n    command: echo (a)")) == [.refused])
        #expect(problems(yaml("services:\n  web:\n    image: a\n    environment:\n      A: x\n    command: echo $A"))
            == [.environmentVariable])
        #expect(problems(yaml("services:\n  web:\n    image: a\n    entrypoint: sh -c\n    command: echo hi"))
            == [.splitScript])
        #expect(problems(yaml("services:\n  web:\n    image: a\n    entrypoint: [\"npm run dev\"]")) == [.programWithSpaces])
        #expect(problems(dockerfile("FROM scratch") + yaml("services:\n  web:\n    build: .\n    command: [\"a b\"]"))
            == [.programWithSpaces])
        #expect(problems(yaml("services:\n  web:\n    image: a\n    command: [\"a b\"]")).isEmpty)
        #expect(problems(yaml("services:\n  web:\n    image: a\n    entrypoint: a b\n    command: [\"c d\"]")).isEmpty)
        #expect(problems(yaml("services:\n  web:\n    image: a\n    command: [\"sh\", \"-c\", \"exec $$0\", \"x\"]"))
            .isEmpty)
    }

    @Test func wording() {
        let report = check(yaml("services:\n  web:\n    image: a\n    command: echo \"$$X\" && ls"))
        let truncated = report.findings.first { $0.slip == .stringRunsInShell }
        #expect(truncated?.explanation.contains("`command: [\"sh\", \"-c\", \"echo \\\"$$X\\\" && ls\"]`") == true)
        #expect(truncated?.claim.sentence == "command: echo \"$$X\" && ls")
        let listed = check(yaml("services:\n  web:\n    image: a\n    entrypoint: [\"npm run dev\"]"))
        #expect(listed.findings.first?.claim.sentence == "entrypoint: [\"npm run dev\"]")
        #expect(listed.findings.first?.explanation.contains("[\"npm\", \"run\", \"dev\"]") == true)
    }
}
