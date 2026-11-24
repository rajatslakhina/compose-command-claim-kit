/// Reads an answer's claims about what compose services run and judges each against compose's reading of the
/// compose file, the Dockerfile and the variables the conversation shows.
public struct CommandClaimChecker: Sendable {
    public let reader: CommandClaimReader

    public init(checksFileLines: Bool = true) {
        reader = CommandClaimReader(checksFileLines: checksFileLines)
    }

    /// What the answer and its context (the question, earlier turns) show.
    public func scene(for text: String, context: String = "") -> CommandScene {
        SceneReader.read(answer: text, context: context, earlier: nil)
    }

    public func claims(in text: String, context: String = "") -> [CommandClaim] {
        reader.claims(in: text, scene: scene(for: text, context: context))
    }

    public func judge(_ claim: CommandClaim, in scene: CommandScene) -> CommandFinding {
        CommandEvaluator(scene: scene).judge(claim)
    }

    public func check(_ text: String, context: String = "") -> CommandReport {
        check(text, context: context, earlier: nil).report
    }

    func check(_ text: String, context: String, earlier: CommandScene?)
        -> (report: CommandReport, scene: CommandScene) {
        let scene = SceneReader.read(answer: text, context: context, earlier: earlier)
        let evaluator = CommandEvaluator(scene: scene)
        let findings = reader.claims(in: text, scene: scene).map(evaluator.judge)
        return (CommandReport(findings: findings), scene)
    }
}

/// Checks the answers of one conversation in turn: a compose file, Dockerfile or `.env` shown in an earlier answer
/// still counts for a later one (a turn that shows its own uses those), and a mistake stated again after it was
/// flagged is marked as repeated.
public actor CommandLedger {
    public struct Statistics: Sendable, Hashable {
        public var reviews = 0
        public var claims = 0
        public var flagged = 0
        public var repeated = 0
    }

    public nonisolated let checker: CommandClaimChecker
    public private(set) var statistics = Statistics()
    private var scene: CommandScene?
    private var flaggedBefore: Set<CommandClaim.Kind> = []

    public init(checker: CommandClaimChecker = CommandClaimChecker()) {
        self.checker = checker
    }

    public func review(_ text: String, context: String = "") -> CommandReport {
        let (report, scene) = checker.check(text, context: context, earlier: scene)
        self.scene = scene
        let findings = report.findings.map { finding in
            var marked = finding
            if finding.severity >= .caution, flaggedBefore.contains(finding.claim.kind) { marked.isRepeated = true }
            return marked
        }
        let marked = CommandReport(findings: findings)
        flaggedBefore.formUnion(marked.flagged.map(\.claim.kind))
        statistics.reviews += 1
        statistics.claims += marked.findings.count
        statistics.flagged += marked.flagged.count
        statistics.repeated += marked.repeatedCount
        return marked
    }

    /// Starts a new conversation.
    public func forget() {
        scene = nil
        flaggedBefore = []
    }
}
