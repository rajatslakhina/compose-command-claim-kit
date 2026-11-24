@testable import ComposeCommandClaimKit
import Testing

@Suite("Reading claims")
struct ReaderTests {
    let checker = CommandClaimChecker()
    let file = yaml("""
    services:
      web:
        image: node:20
        command: npm run dev
      db:
        image: postgres:16
    """)

    func kinds(_ text: String, context: String = "") -> [CommandClaim.Kind] {
        checker.claims(in: text, context: context).map(\.kind)
    }

    @Test func runsClaims() {
        #expect(kinds(file + "`web` runs `npm run dev`.") == [.runs(service: "web", stated: "npm run dev", run: nil)])
        #expect(kinds(file + "The web service starts `npm run dev`.")
            == [.runs(service: "web", stated: "npm run dev", run: nil)])
        #expect(kinds(file + "It runs `npm run dev`.") == [.runs(service: "web", stated: "npm run dev", run: nil)])
        #expect(kinds(file + "`npm run dev` becomes `npm run dev`.")
            == [.runs(service: "web", stated: "npm run dev", run: nil)])
        #expect(kinds(file + "`npm start` becomes `x`.").isEmpty)
        #expect(kinds(file + "`$TAG` runs `x`.").isEmpty)
        #expect(kinds(file + "`web` and `db` run `x`, and `web` runs `y` instead of `z`.")
            == [.runs(service: "web", stated: "y", run: nil)])
        #expect(kinds(file + "It runs the whole thing really fast `x`.").isEmpty)
        #expect(kinds(file + "It does not run `x`.").isEmpty)
    }

    @Test(arguments: ["web", "command:", "compose.yaml", "docker compose up", "a: b", "$TAG", ""])
    func notCommands(_ code: String) {
        #expect(kinds(file + "It runs `\(code)`.").isEmpty)
    }

    @Test func serviceBinding() {
        let two = yaml("services:\n  web:\n    image: a\n    command: x\n  api:\n    image: b\n    command: y")
        #expect(kinds(two + "It runs `x`.") == [.runs(service: nil, stated: "x", run: nil)])
        #expect(kinds(two + "`web` and `api` start; it runs `x`.") == [.runs(service: nil, stated: "x", run: nil)])
        #expect(kinds(two + "The api container is fine; it runs `y`.")
            == [.runs(service: "api", stated: "y", run: nil)])
        #expect(kinds("Compose: it runs `x`.") == [.runs(service: nil, stated: "x", run: nil)])
    }

    @Test func runLines() {
        let run = RunCommand.parse("docker compose run web npm test")
        #expect(kinds(file + "`docker compose run web npm test` runs `npm test`.")
            == [.runs(service: "web", stated: "npm test", run: run)])
        let block = file + "\(fence)sh\ndocker compose run web npm test\n\(fence)\n"
        #expect(kinds(block + "This runs `npm test`.") == [.runs(service: "web", stated: "npm test", run: run)])
        #expect(kinds(block + "Then `web` runs `npm test`.") == [.runs(service: "web", stated: "npm test", run: nil)])
        let two = file + "\(fence)sh\ndocker compose run web a\ndocker compose run web b\n\(fence)\n"
        #expect(kinds(two + "This runs `a`.") == [.runs(service: "web", stated: "a", run: nil)])
    }

    @Test func variableClaims() {
        let greeter = yaml("services:\n  web:\n    image: a\n    command: echo $GREETING\n  db:\n    image: b")
        #expect(kinds(greeter + "`$GREETING` becomes `hi`.")
            == [.variable(service: "web", token: "$GREETING", stated: "hi")])
        #expect(kinds(greeter + "Here `$GREETING` is just `hi`.")
            == [.variable(service: "web", token: "$GREETING", stated: "hi")])
        #expect(kinds(greeter + "`$GREETING` is not `hi`.").isEmpty)
        #expect(kinds(greeter + "`$GREETING` and `hi`.").isEmpty)
        #expect(kinds(greeter + "`$OTHER` becomes `x`.") == [.variable(service: "web", token: "$OTHER", stated: "x")])
    }

    @Test func filters() {
        #expect(kinds(file + "Does `web` run `npm run dev`?").isEmpty)
        #expect(kinds(file + "Use `npm start` instead.").isEmpty)
        #expect(kinds(file + "You might expect it runs `x`.").isEmpty)
        #expect(kinds("`web` runs `x`.").isEmpty)
        let manifest = yaml("apiVersion: v1\nkind: Pod")
        #expect(kinds(manifest + "Compose runs `command` through a shell.").isEmpty)
        #expect(CommandClaimChecker(checksFileLines: false).claims(in: yaml("services:\n  web:\n    command: a && b"))
            .isEmpty)
    }

    @Test func rules() {
        let claims = kinds("In compose, `command` is wrapped in `/bin/sh -c`; `&&` is passed literally.")
        #expect(claims == [
            .rule(.stringRunsInShell, negated: false, token: nil, service: nil, emptyValue: false),
            .rule(.operatorPassedAsArgument, negated: false, token: nil, service: nil, emptyValue: false)
        ])
        #expect(kinds("Compose: `command: sh -c \"a && b\"` runs it through a shell.").isEmpty)
        #expect(kinds("Compose: with `command: sh -c \"a && b\"` the string is run by a shell.").isEmpty)
        #expect(kinds("Compose: the `command` string needs a shell for `&&` to work.").isEmpty)
        #expect(kinds("An empty `entrypoint: \"\"` keeps the image's `CMD` in compose.")
            == [.rule(.entrypointKeepsImageCmd, negated: false, token: nil, service: nil, emptyValue: true)])
        #expect(kinds("In compose `$$HOME` is expanded in the container.")
            == [.rule(.variablesFromContainer, negated: false, token: "$$HOME", service: nil, emptyValue: false)])
    }
}
