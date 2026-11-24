import DockerfileClaimKit
import EntrypointClaimKit

/// What the conversation shows that decides what compose services run: the compose file, the Dockerfile its
/// `build:` services use, the variables compose substitutes, and whether the talk is about compose at all.
public struct CommandScene: Sendable, Hashable {
    /// The compose file the claims are judged against.
    public internal(set) var project: ComposeProject?
    /// Why there is no project to judge against; `nil` when there is one.
    public var projectNote: String? {
        project == nil ? noProjectReason : nil
    }

    var noProjectReason = "the conversation shows no compose file"
    /// The image config of the one Dockerfile shown, for services with `build:`.
    public internal(set) var image: ImageCommands?
    public internal(set) var variables = Variables()
    /// The conversation is about Docker Compose.
    public internal(set) var aboutCompose = false
    /// The answer shows a Kubernetes manifest, whose `command:` means the opposite: nothing is read.
    public internal(set) var kubernetes = false
    /// Compose files shown in the answer itself: their lines are checked.
    var answerFiles: [ComposeProject] = []

    public init() {}

    /// The image a service starts from, when the conversation shows its Dockerfile.
    func image(for service: ComposeService) -> ImageCommands? {
        service.builds ? image : nil
    }
}

enum BlockKind: Equatable {
    case compose
    case kubernetes
    case dockerfile
    case env
    case shell
    case prose
}

enum SceneReader {
    static func kind(of block: AnswerBlock, after prose: String) -> BlockKind {
        guard case let .code(info) = block.kind else { return .prose }
        let text = block.text
        let topLevel = block.lines.filter { $0.first.map { !$0.isWhitespace } == true }
        if topLevel.contains(where: { $0.hasPrefix("apiVersion:") || $0.hasPrefix("kind:") }) { return .kubernetes }
        if ComposeProject.looksLikeCompose(text) { return .compose }
        let tag = String(info.prefix { !" :{".contains($0) })
        if tag == "dockerfile" || (!["yaml", "yml"].contains(tag) && Dockerfile.looksLikeDockerfile(text)) {
            return .dockerfile
        }
        if ["env", "dotenv"].contains(tag) || info.contains(".env")
            || (EnvFile.looksLikeEnvFile(block.lines) && prose.contains(".env")) {
            return .env
        }
        return .shell
    }

    /// The blocks of a text with their kinds.
    static func classify(_ text: String) -> [(block: AnswerBlock, kind: BlockKind)] {
        var previous = ""
        return AnswerBlocks.split(text).map { block in
            let kind = kind(of: block, after: previous)
            if kind == .prose { previous = block.lines.last { !$0.trimmed.isEmpty }?.folded ?? "" }
            return (block, kind)
        }
    }

    static func read(answer: String, context: String, earlier: CommandScene?) -> CommandScene {
        let answerBlocks = classify(answer)
        let contextBlocks = classify(context)
        var scene = CommandScene()
        scene.variables = variables(answerBlocks, contextBlocks, earlier: earlier?.variables ?? Variables())
        scene.kubernetes = (answerBlocks + contextBlocks).contains { $0.kind == .kubernetes }
        let dockerfiles = answerBlocks.filter { $0.kind == .dockerfile }
        let contextDockerfiles = contextBlocks.filter { $0.kind == .dockerfile }
        let shownDockerfiles = dockerfiles.isEmpty ? contextDockerfiles : dockerfiles
        if shownDockerfiles.isEmpty {
            scene.image = earlier?.image
        } else if shownDockerfiles.count == 1 {
            scene.image = ImageCommands(Dockerfile(shownDockerfiles[0].block.text))
        }
        let files = answerBlocks.filter { $0.kind == .compose }.map(\.block.text)
        let contextFiles = contextBlocks.filter { $0.kind == .compose }.map(\.block.text)
        let readings = files.map { ComposeProject.read($0, variables: scene.variables) }
        // File lines are checked on the answer's last compose file, unless it quotes one the question showed.
        let quoted = Set(contextFiles.map(StatedWords.normalized))
        if let last = files.last, !quoted.contains(StatedWords.normalized(last)),
           case let .project(project)? = readings.last {
            scene.answerFiles = [project]
        }
        let shown = files.isEmpty ? contextFiles.map { ComposeProject.read($0, variables: scene.variables) } : readings
        switch (shown.count, shown.first) {
        case (0, _):
            scene.project = earlier.flatMap { reread($0, scene.variables) }
            if let earlier, scene.project == nil { scene.noProjectReason = earlier.noProjectReason }
        case let (1, .project(project)?):
            scene.project = project
        case let (1, .unfollowed(reason)?):
            scene.noProjectReason = "the compose file uses \(reason), which this reader does not follow"
        case (1, _):
            scene.noProjectReason = "the compose file has no `services:` mapping"
        default:
            scene.noProjectReason = "the answer shows several compose files; how they merge is not read here"
        }
        let folded = (answer + "\n" + context).folded
        scene.aboutCompose = !files.isEmpty || !contextFiles.isEmpty || scene.project != nil
            || folded.contains("compose")
        return scene
    }

    /// An earlier turn's project read again with this turn's variables.
    static func reread(_ earlier: CommandScene, _ variables: Variables) -> ComposeProject? {
        guard let project = earlier.project else { return nil }
        return ComposeProject(services: project.services.map { $0.reread(variables) })
    }

    static func variables(_ answer: [(block: AnswerBlock, kind: BlockKind)],
                          _ context: [(block: AnswerBlock, kind: BlockKind)], earlier: Variables) -> Variables {
        var variables = earlier
        for (block, kind) in context + answer {
            switch kind {
            case .env:
                for (name, value) in EnvFile.parse(block.lines) { variables.dotEnv[name] = value }
            case .shell:
                let exports = block.lines.map(\.trimmed).filter { $0.hasPrefix("export ") }
                for (name, value) in EnvFile.parse(exports) { variables.shell[name] = value }
            default:
                break
            }
        }
        return variables
    }
}
