@testable import ComposeCommandClaimKit
import Testing

@Suite("What a conversation shows")
struct SceneTests {
    let checker = CommandClaimChecker()

    @Test func blockKinds() {
        let text = """
        Put this in `.env`:
        \(fence)
        TAG=1.2
        \(fence)
        \(fence)ini title=".env"
        A=1
        \(fence)
        \(fence)env
        B=2
        \(fence)
        \(fence)sh
        export GREETING=hi
        docker compose up
        \(fence)
        \(fence)
        FROM node:20
        CMD ["node", "app.js"]
        \(fence)
        \(fence)yaml
        FROM: not a dockerfile
        \(fence)
        \(fence)yaml
        apiVersion: v1
        kind: Pod
        \(fence)
        \(fence)yaml
        services:
          web:
            build: .
        \(fence)
        """
        let kinds = SceneReader.classify(text).map(\.kind)
        #expect(kinds == [.prose, .env, .env, .env, .shell, .dockerfile, .shell, .kubernetes, .compose])
        let scene = checker.scene(for: text)
        #expect(scene.variables.dotEnv == ["TAG": "1.2", "A": "1", "B": "2"])
        #expect(scene.variables.shell == ["GREETING": "hi"])
        #expect(scene.kubernetes && scene.aboutCompose)
        #expect(scene.image?.cmd.words == ["node", "app.js"])
    }

    @Test func dockerfilePrecedence() {
        let one = dockerfile("FROM scratch\nCMD [\"a\"]")
        let two = dockerfile("FROM scratch\nCMD [\"b\"]")
        #expect(checker.scene(for: one + two).image == nil)
        #expect(checker.scene(for: "text", context: one).image?.cmd.words == ["a"])
        #expect(checker.scene(for: two, context: one).image?.cmd.words == ["b"])
    }

    @Test func composePrecedence() {
        let file = yaml("services:\n  web:\n    image: a\n    command: echo $TAG")
        #expect(checker.scene(for: "text", context: file).project?.service("web") != nil)
        #expect(checker.scene(for: "text").projectNote == "the conversation shows no compose file")
        #expect(checker.scene(for: "text").aboutCompose == false)
        #expect(checker.scene(for: "docker compose up").aboutCompose)
        #expect(checker.scene(for: file + file).projectNote?.contains("several compose files") == true)
        #expect(checker.scene(for: yaml("services:\n  web: *x")).projectNote?.contains("an alias") == true)
        let first = checker.scene(for: file)
        let later = SceneReader.read(answer: yaml("x: 1") + "\(fence)env\nTAG=2\n\(fence)", context: "", earlier: first)
        #expect(later.project?.service("web")?.command?.words == ["echo", "2"])
        let none = SceneReader.read(answer: "text", context: "", earlier: checker.scene(for: "nothing"))
        #expect(none.project == nil && none.projectNote == "the conversation shows no compose file")
        #expect(SceneReader.reread(CommandScene(), Variables()) == nil)
    }
}
