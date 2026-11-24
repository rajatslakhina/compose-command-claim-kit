@testable import ComposeCommandClaimKit
import DockerfileClaimKit
import EntrypointClaimKit
import Testing

@Suite("Services, settings and processes")
struct ModelTests {
    @Test func settingsRead() throws {
        let web = try #require(service("""
        services:
          web:
            build: .
            environment:
              GREETING: hi
              EMPTY:
            entrypoint: ["/sbin/tini", "--"]
            command: cd /app && npm start
        """))
        #expect(web.builds && web.image == nil)
        #expect(web.environment == ["GREETING": "hi", "EMPTY": ""])
        #expect(web.entrypoint?.words == ["/sbin/tini", "--"])
        #expect(web.command?.words == ["cd", "/app"])
        #expect(web.command?.text == "cd /app && npm start")
        #expect(web.entrypoint?.text == nil)
        #expect(web.command?.shellReading == ["/bin/sh", "-c", "cd /app && npm start"])
        #expect(web.entrypoint?.shellReading == nil)
        #expect(web.settings.map(\.key) == ["entrypoint", "command"])
        #expect(web.unknownReason == "`web`'s command is not known")
    }

    @Test func environmentList() throws {
        let web = try #require(service("""
        services:
          web:
            image: x
            environment:
              - A=1
              - B
            command: null
        """))
        #expect(web.environment == ["A": "1"])
        #expect(web.command == nil)
    }

    @Test func listsAndOddValues() throws {
        let file = """
        services:
          web:
            image: x
            command: ["npm run dev", "$$HOME", "$TAG"]
          bad:
            image: x
            command:
              - a: 1
          map:
            image: x
            entrypoint:
              key: value
          broken:
            image: x
            command: ["${A:?gone}"]
          empty:
            image: x
            command: []
        """
        let variables = Variables(dotEnv: ["TAG": "1"], unset: ["A"])
        let web = try #require(service(file, variables: variables))
        #expect(web.command?.words == ["npm run dev", "$HOME", "1"])
        #expect(web.command?.splitItems == ["npm", "run", "dev", "$HOME", "1"])
        #expect(web.command?.isEmpty == false)
        #expect(web.escapedNames == ["HOME"] && web.substitutedNames == ["TAG"])
        #expect(service(file, "bad")?.command?.reading == .unfollowed("a list item that is not a plain value"))
        #expect(service(file, "map")?.entrypoint?.reading == .unfollowed("a mapping where a command belongs"))
        #expect(service(file, "broken", variables: variables)?.unknownReason.contains("is required") == true)
        #expect(service(file, "map")?.unknownReason.contains("which this reader does not follow") == true)
        #expect(service(file, "empty")?.command?.isEmpty == true)
        #expect(service(file, "empty")?.command?.splitItems == nil)
    }

    @Test func stringFailures() throws {
        let file = """
        services:
          web:
            image: x
            command: echo (a)
          dollar:
            image: x
            command: echo $1
          tick:
            image: x
            command: "echo `a"
          shell:
            image: x
            command: echo $TAG
        """
        #expect(service(file)?.command?.reading == .refused(CommandWords.invalid))
        #expect(service(file)?.unknownReason.contains("refuses this file") == true)
        #expect(service(file, "dollar")?.command?.reading == .unfollowed("a `$` this reader does not follow"))
        #expect(service(file, "tick")?.command?.reading == .unfollowed("an unclosed backtick"))
        let shell = try #require(service(file, "shell"))
        #expect(shell.command?.words == nil && shell.command?.unknownVariables == ["TAG"])
        #expect(shell.unknownReason.contains("`$TAG`"))
        #expect(shell.reread(Variables(shell: ["TAG": "2"])).command?.words == ["echo", "2"])
    }

    @Test func projects() {
        #expect(ComposeProject.read("apiVersion: v1\nkind: Pod\nservices: {}") == .notCompose)
        #expect(ComposeProject.read("just: text") == .notCompose)
        #expect(ComposeProject.read("not yaml: [") == .notCompose)
        #expect(ComposeProject.read("services:\n  web: &x\n    image: a") == .unfollowed("an anchor (line 2)"))
        #expect(project("services:\n  web:\n    image: a")?.service("web")?.image == "a")
        #expect(project("services:\n  web:\n    image: a")?.service("db") == nil)
        #expect(ComposeProject.looksLikeCompose("services:\n  web: {}"))
        #expect(!ComposeProject.looksLikeCompose("services:\nkind: x"))
    }

    @Test func runLines() {
        let full = RunCommand.parse("$ docker compose -f a.yml --project-name=p run --rm -e A=1 --name=x --entrypoint "
            + "\"/bin/sh -c\" web echo hi")
        #expect(full?.service == "web" && full?.entrypoint == ["/bin/sh", "-c"] && full?.arguments == ["echo", "hi"])
        #expect(RunCommand.parse("sudo docker-compose run web")?.arguments == [])
        #expect(RunCommand.parse("docker compose run --entrypoint= web")?.entrypoint == [])
        #expect(RunCommand.parse("docker compose up -d") == nil)
        #expect(RunCommand.parse("docker run web") == nil)
        #expect(RunCommand.parse("npm test") == nil)
        #expect(RunCommand.parse("docker compose --unknown run web") == nil)
        #expect(RunCommand.parse("docker compose -f") == nil)
        #expect(RunCommand.parse("docker compose run --weird web") == nil)
        #expect(RunCommand.parse("docker compose run -e") == nil)
        #expect(RunCommand.parse("docker compose run --entrypoint 'a && b' web") == nil)
        #expect(RunCommand.parse("docker compose run --rm") == nil)
    }

    @Test func statedWords() {
        #expect(StatedWords.split("sh -c \"cd /app && npm start\" 'a b' c\\ d") == ["sh", "-c", "cd /app && npm start",
                                                                                   "a b", "c d"])
        #expect(StatedWords.split("\"\"") == [""])
        #expect(StatedWords.normalized("  a \n b ") == "a b")
    }

    @Test func processes() {
        let image = ImageCommands(Dockerfile("FROM scratch\nENTRYPOINT [\"/entry.sh\"]\nCMD [\"serve\"]\n"))
        #expect(ContainerProcess.start(entrypoint: ["/a"], command: nil, image: image).words == ["/a"])
        #expect(ContainerProcess.start(entrypoint: [], command: nil, image: image).words == ["serve"])
        #expect(ContainerProcess.start(entrypoint: nil, command: [], image: image).words == ["/entry.sh", "serve"])
        #expect(ContainerProcess.start(entrypoint: nil, command: ["x"], image: nil).words == nil)
        #expect(ContainerProcess.start(entrypoint: nil, command: nil, image: nil).command == nil)
        let none = ImageCommands(Dockerfile("FROM scratch\nLABEL a=b\n"))
        #expect(ContainerProcess.start(entrypoint: nil, command: nil, image: none).isRefused)
        #expect(ContainerProcess(entrypoint: [], command: ["sh", "-c", "x", "y"]).shellScript?.rest == ["y"])
        #expect(ContainerProcess(entrypoint: [], command: ["sh", "-x"]).shellScript == nil)
        #expect(ContainerProcess(entrypoint: [], command: ["a b", "c"]).display == "\"a b\" c")
        #expect(ContainerProcess(entrypoint: nil, command: ["c"]).display == nil)
        #expect(ContainerProcess.handsOn([]) && ContainerProcess.handsOn(["/x", "--"])
            && ContainerProcess.handsOn(["tini"]) && ContainerProcess.handsOn(["docker-entrypoint.sh"])
            && !ContainerProcess.handsOn(["python", "manage.py"]))
    }

    @Test func matching() {
        let known = ContainerProcess(entrypoint: ["/sbin/tini", "--"], command: ["npm", "start"])
        #expect(known.matches(words: ["/sbin/tini", "--", "npm", "start"], text: "") == .yes)
        #expect(known.matches(words: ["npm", "start"], text: "npm start") == .yes)
        #expect(known.matches(words: ["npm"], text: "npm") == .no)
        let shell = ContainerProcess(entrypoint: [], command: ["sh", "-c", "cd /app &&  npm start"])
        #expect(shell.matches(words: [], text: "cd /app && npm start") == .yes)
        let unseen = ContainerProcess(entrypoint: nil, command: ["npm", "start"])
        #expect(unseen.matches(words: ["npm", "start"], text: "npm start") == .yes)
        #expect(unseen.matches(words: ["x", "npm", "start"], text: "x npm start") == .possible)
        #expect(unseen.matches(words: ["npm"], text: "npm") == .no)
        let unseenShell = ContainerProcess(entrypoint: nil, command: ["sh", "-c", "a && b"])
        #expect(unseenShell.matches(words: [], text: "a && b") == .yes)
        #expect(ContainerProcess(entrypoint: nil, command: nil).matches(words: ["x"], text: "x") == .possible)
        #expect(ContainerProcess(entrypoint: nil, command: []).matches(words: [], text: "") == .no)
    }
}
