/// Reads what an answer claims about the processes compose services start: "`web` runs `npm run dev`", "`$GREETING`
/// becomes `hi`", rules ("Compose runs `command` through a shell"), and the `command:` and `entrypoint:` lines of
/// the compose files it shows. Nothing is read from a conversation that is not about compose, or from an answer
/// with a Kubernetes manifest (its `command:` replaces the image's ENTRYPOINT).
public struct CommandClaimReader: Sendable {
    public let checksFileLines: Bool

    public init(checksFileLines: Bool = true) {
        self.checksFileLines = checksFileLines
    }

    public func claims(in text: String, scene: CommandScene) -> [CommandClaim] {
        guard !scene.kubernetes, scene.aboutCompose else { return [] }
        var claims: [CommandClaim] = []
        if checksFileLines {
            claims = scene.answerFiles.flatMap { FileChecks.claims($0, scene: scene) }
        }
        var lastRun: RunCommand?
        for block in AnswerBlocks.split(text) {
            guard case .prose = block.kind else {
                let runs = block.lines.compactMap(RunCommand.parse)
                lastRun = runs.count == 1 ? runs[0] : nil
                continue
            }
            // A paragraph about Kubernetes states its rules, where `command:` replaces the ENTRYPOINT.
            let kubernetes = ["kubernetes", "k8s", "kubectl", "pod spec", "podspec", "a pod"]
            let rules = !Words.containsAny(block.text.folded, kubernetes)
            for sentence in Sentences.split(block.lines) where !sentence.hasSuffix("?") {
                claims += read(sentence, previousRun: lastRun, scene: scene, rules: rules)
            }
            lastRun = nil
        }
        return claims
    }

    func read(_ sentence: String, previousRun: RunCommand?, scene: CommandScene,
              rules: Bool = true) -> [CommandClaim] {
        let sentenceRun = Sentences.codeSpans(sentence).compactMap(RunCommand.parse).last
        let pointsBack = ["this", "that", "it", "here"].contains {
            sentence.folded.hasPrefix($0 + " ") || sentence.folded.hasPrefix($0 + ",")
        }
        let run = sentenceRun ?? (pointsBack ? previousRun : nil)
        var claims: [CommandClaim] = []
        for raw in Sentences.clauses(sentence) {
            let clause = Clause(raw)
            guard !clause.isInstruction, !clause.isHypothetical else { continue }
            let stated = rules ? rule(clause, sentence: sentence, scene: scene) : nil
            if let claim = stated ?? variable(clause, sentence, scene)
                ?? runs(clause, sentence, run: run, scene: scene) {
                claims.append(claim)
            }
        }
        return claims
    }

    func rule(_ clause: Clause, sentence: String, scene: CommandScene) -> CommandClaim? {
        for cue in RuleCues.all where cue.topic(clause) {
            guard let phrase = cue.phrases.first(where: { Words.contains(clause.plain, $0) }),
                  !cue.excludes.contains(where: { Words.contains(clause.plain, $0) }) else { continue }
            let negations = Sentences.negationCount(clause.plain.replacingOccurrences(of: phrase, with: " "))
            // Two denials in one clause ("doesn't run it in a shell and doesn't expand `~`") are not read.
            guard negations <= 1 else { return nil }
            let token = clause.variableToken
            let empty = RuleCues.emptyEntrypoint(clause)
            let service = token.flatMap { Self.service(using: $0, scene) } ?? Self.service(in: clause, sentence, scene)
            return CommandClaim(kind: .rule(cue.rule, negated: negations % 2 == 1, token: token, service: service,
                                            emptyValue: empty), sentence: sentence)
        }
        return nil
    }

    static let valueVerbs = ["expands to", "becomes", "resolves to", "is replaced with", "is replaced by",
                             "turns into", "is substituted with", "evaluates to", "is set to", "will be", "is"]

    func variable(_ clause: Clause, _ sentence: String, _ scene: CommandScene) -> CommandClaim? {
        let pieces = Sentences.pieces(clause.text)
        guard Sentences.negationCount(clause.prose) == 0 else { return nil }
        for index in stride(from: 1, to: pieces.count - 2, by: 2) where Clause.isVariable(pieces[index].text) {
            let between = pieces[index + 1].text.folded.trimmed
            guard Self.valueVerbs.contains(between) || Self.valueVerbs.contains(where: { between == $0 + " just" })
            else { continue }
            let token = pieces[index].text
            let service = Self.service(using: token, scene) ?? Self.service(in: clause, sentence, scene)
            return CommandClaim(kind: .variable(service: service, token: token, stated: pieces[index + 2].text),
                                sentence: sentence)
        }
        return nil
    }

    static let runVerbs = ["runs", "will run", "starts", "will start", "executes", "will execute", "launches",
                           "ends up running", "is executed", "gets executed", "runs as", "the process is",
                           "the command is", "pid 1 is", "execs", "becomes", "is equivalent to", "turns into",
                           "comes out as", "is read as", "is split into"]
    /// Verbs whose subject must be the command string itself (`npm run dev` becomes ...).
    static let subjectVerbs: Set<String> = ["becomes", "is equivalent to", "turns into", "comes out as", "is read as",
                                            "is split into"]
    static let stopWords: Set<String> = ["instead", "than", "after", "before", "not", "unless", "if", "of", "when"]

    func runs(_ clause: Clause, _ sentence: String, run: RunCommand?, scene: CommandScene) -> CommandClaim? {
        guard Sentences.negationCount(clause.prose) == 0 else { return nil }
        let pieces = Sentences.pieces(clause.text)
        for index in stride(from: 0, to: pieces.count - 1, by: 2) {
            let text = pieces[index].text.folded
            let found = Self.runVerbs.compactMap { verb in Words.position(text, verb).map { (verb, $0) } }
            guard let (verb, position) = found.min(by: { $0.1 < $1.1 }) else { continue }
            let after = text[text.index(position, offsetBy: verb.count)...].split(whereSeparator: \.isWhitespace)
            guard after.count <= 3, !after.contains(where: { Self.stopWords.contains(String($0)) }) else { continue }
            let stated = pieces[index + 1].text
            guard Self.isCommand(stated, scene: scene) else { continue }
            let subjects = stride(from: 1, to: index, by: 2).map { pieces[$0].text }
            if subjects.contains(where: Clause.isVariable) { return nil }
            let service: String?
            if Self.subjectVerbs.contains(verb) {
                guard let named = subjects.lazy.compactMap({ Self.service(writing: $0, scene) }).first else {
                    return nil
                }
                service = named
            } else {
                service = run?.service ?? Self.service(in: clause, sentence, scene)
            }
            return CommandClaim(kind: .runs(service: service, stated: stated, run: run), sentence: sentence)
        }
        return nil
    }

    /// Code that reads as a command line, not as a key, a service, a file or a `docker` command.
    static func isCommand(_ code: String, scene: CommandScene) -> Bool {
        let folded = code.folded.trimmed
        let keys = ["command", "command:", "entrypoint", "entrypoint:", "cmd", "environment", "environment:"]
        guard !folded.isEmpty, !keys.contains(folded), !Clause.isVariable(code) else { return false }
        if scene.project?.service(code) != nil { return false }
        if folded.hasPrefix("docker ") || folded.hasPrefix("docker-compose") || folded.contains("compose.y")
            || folded.hasSuffix(".yml") || folded.hasSuffix(".yaml") || folded == "dockerfile" {
            return false
        }
        return !folded.contains(": ")
    }

    /// The service a clause names (as code, or as "the web service"), else the sentence, else the only one that
    /// sets a command.
    static func service(in clause: Clause, _ sentence: String, _ scene: CommandScene) -> String? {
        guard let project = scene.project else { return nil }
        let names = project.services.map(\.name)
        for source in [clause.text, sentence] {
            let codes = Sentences.codeSpans(source)
            let plain = Sentences.plain(source)
            let found = names.filter { name in
                codes.contains(name) || Words.containsAny(plain, [name.folded + " service", name.folded + " container"])
            }
            if found.count == 1 { return found[0] }
            if found.count > 1 { return nil }
        }
        if project.services.count == 1 { return project.services[0].name }
        let setting = project.services.filter { !$0.settings.isEmpty }
        return setting.count == 1 ? setting[0].name : nil
    }

    /// The one service whose `command:` or `entrypoint:` writes this variable.
    static func service(using token: String, _ scene: CommandScene) -> String? {
        let users = scene.project?.services.filter { service in
            service.settings.flatMap(\.writtenTexts).contains { $0.contains(token) }
        } ?? []
        return users.count == 1 ? users[0].name : nil
    }

    /// The one service whose `command:` or `entrypoint:` is written as this text.
    static func service(writing text: String, _ scene: CommandScene) -> String? {
        let target = StatedWords.normalized(text)
        let writers = scene.project?.services.filter { service in
            service.settings.compactMap(\.text).contains { StatedWords.normalized($0) == target }
        } ?? []
        return writers.count == 1 ? writers[0].name : nil
    }
}
