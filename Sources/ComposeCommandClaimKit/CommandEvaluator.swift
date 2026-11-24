import EntrypointClaimKit

/// Judges claims against what compose starts for each service in a scene.
struct CommandEvaluator {
    let scene: CommandScene

    /// A stated command line: its words and its text.
    struct Stated {
        let words: [String]
        let text: String
    }

    /// A stated rule, unpacked from the claim.
    struct RuleClaim {
        let rule: Rule
        let negated: Bool
        let token: String?
        let service: String?
        let empty: Bool
    }

    func judge(_ claim: CommandClaim) -> CommandFinding {
        switch claim.kind {
        case let .runs(service, stated, run):
            let words = Stated(words: StatedWords.split(stated), text: stated)
            return lookup(service, claim, judge: { runs(claim, $0, stated: words, run: run) })
        case let .variable(service, token, stated):
            return lookup(service, claim, judge: { variable(claim, $0, token: token, stated: stated) })
        case let .rule(rule, negated, token, service, empty):
            return self.rule(claim, RuleClaim(rule: rule, negated: negated, token: token, service: service,
                                              empty: empty))
        case let .fileLine(service, key, line, problem):
            return fileLine(claim, service: service, key: key, line: line, problem: problem)
        }
    }

    func unchecked(_ claim: CommandClaim, _ reason: String) -> CommandFinding {
        CommandFinding(claim: claim, outcome: .unchecked(reason))
    }

    func lookup(_ name: String?, _ claim: CommandClaim, judge: (ComposeService) -> CommandFinding) -> CommandFinding {
        guard let project = scene.project else { return unchecked(claim, scene.noProjectReason) }
        guard let name, let service = project.service(name) else {
            return unchecked(claim, "the sentence names no service of the compose file")
        }
        return judge(service)
    }

    func runs(_ claim: CommandClaim, _ service: ComposeService, stated: Stated, run: RunCommand?) -> CommandFinding {
        let image = scene.image(for: service)
        guard let actual = ContainerProcess.of(service, image: image, run: run) else {
            return fromShell(claim, service, image: image, run: run, stated: stated)
                ?? unchecked(claim, service.unknownReason)
        }
        let match = actual.matches(words: stated.words, text: stated.text)
        if match == .yes { return CommandFinding(claim: claim, outcome: .exact) }
        if match == .no,
           Misreadings.entrypointPrefix(service, image: image, run: run, actual: actual, stated: stated.words) {
            return CommandFinding(claim: claim, outcome: .caveat(.entrypointPrefix),
                                  actual: Wording.prefixed(service, actual))
        }
        let alternatives = Misreadings.alternatives(service, image: image, run: run, actual: actual,
                                                    variables: scene.variables)
        if let alternative = alternatives.first(where: {
            $0.process.matches(words: stated.words, text: stated.text) == .yes
        }) {
            return CommandFinding(claim: claim, outcome: .wrong(alternative.slip),
                                  actual: Wording.runs(alternative, service: service, actual: actual, run: run))
        }
        if match == .possible {
            return unchecked(claim, "the image's ENTRYPOINT, which the conversation does not show, comes first")
        }
        return unchecked(claim, "it differs from what compose starts (\(Wording.process(actual))), and no known "
                             + "misreading explains it")
    }

    /// A command whose words wait on variables the conversation does not set: the stated line holds if the shell
    /// sets them the way the service's `environment:` does.
    func fromShell(_ claim: CommandClaim, _ service: ComposeService, image: ImageCommands?, run: RunCommand?,
                   stated: Stated) -> CommandFinding? {
        let names = Set(service.settings.flatMap(\.unknownVariables))
        guard !names.isEmpty, names.allSatisfy({ service.environment[$0] != nil }) else { return nil }
        let environment = service.environment.filter { names.contains($0.key) }
        guard let believed = ContainerProcess.of(service.reread(scene.variables.reading(environment: environment)),
                                                 image: image, run: run),
              believed.matches(words: stated.words, text: stated.text) == .yes else { return nil }
        let unset = ContainerProcess.of(service.reread(scene.variables.unsetting(names)), image: image, run: run)
        return CommandFinding(claim: claim, outcome: .caveat(.variableFromShell),
                              actual: Wording.fromShell(service, names: names.sorted(), unset: unset))
    }

    func variable(_ claim: CommandClaim, _ service: ComposeService, token: String, stated: String) -> CommandFinding {
        let (name, escaped) = Clause.variableName(token)
        if escaped { return escapedVariable(claim, service, name: name, stated: stated) }
        let contained = service.environment[name]
        guard scene.variables.knows(name) else {
            if contained == stated {
                return CommandFinding(claim: claim, outcome: .caveat(.variableFromShell),
                                      actual: Wording.fromShell(service, names: [name], unset: nil))
            }
            return unchecked(claim, "compose takes `$\(name)` from your shell, which the conversation does not show")
        }
        guard let value = try? Interpolation.resolve(token, scene.variables).value else {
            return unchecked(claim, "`\(token)` stops `docker compose` (`:?`)")
        }
        if value == stated { return CommandFinding(claim: claim, outcome: .exact) }
        if contained == stated {
            return CommandFinding(claim: claim, outcome: .wrong(.variableReadInContainer),
                                  actual: "Compose substitutes `\(token)` as `\(value)` from your shell or `.env`; "
                                      + "the service's `environment:` value (`\(stated)`) is not used.")
        }
        return unchecked(claim, "compose substitutes `\(token)` as `\(value)`, and no known misreading explains "
                             + "`\(stated)`")
    }

    /// `$$NAME`: a literal `$NAME` in the container, expanded only by a shell the command starts.
    func escapedVariable(_ claim: CommandClaim, _ service: ComposeService, name: String,
                         stated: String) -> CommandFinding {
        guard let process = ContainerProcess.of(service, image: scene.image(for: service), run: nil) else {
            return unchecked(claim, service.unknownReason)
        }
        if let shell = process.commandShellScript, Self.mentions(shell.script, name) {
            if service.environment[name] == stated { return CommandFinding(claim: claim, outcome: .exact) }
            return unchecked(claim, "the container's shell expands `$\(name)` from the container's environment, "
                                 + "which the conversation does not fully show")
        }
        guard process.words != nil else {
            return unchecked(claim, "the image's ENTRYPOINT, which the conversation does not show, may be a shell")
        }
        if stated == "$" + name || stated == "${" + name + "}" { return CommandFinding(claim: claim, outcome: .exact) }
        return CommandFinding(claim: claim, outcome: .wrong(.dollarDollarExpanded),
                              actual: "`\(service.name)` gets a literal `$\(name)`: `$$` passes a `$` through, and "
                                  + "no shell runs the command to expand it.")
    }

    static func mentions(_ script: String, _ name: String) -> Bool {
        script.contains("${" + name) || Words.contains(script, "$" + name)
    }

    func rule(_ claim: CommandClaim, _ stated: RuleClaim) -> CommandFinding {
        var truth = stated.rule.isTrue
        var slip: CommandFinding.Slip? = stated.rule.slip
        let variableRule = stated.rule == .variablesFromContainer || stated.rule == .variablesFromShell
        if let token = stated.token, Clause.variableName(token).escaped, variableRule {
            if stated.rule == .variablesFromShell {
                truth = false
            } else {
                guard let shell = shellRuns(token, stated.service) else {
                    return unchecked(claim, "it depends on whether the command runs a shell, and the service's "
                                         + "command is not known")
                }
                truth = shell
            }
            slip = truth ? nil : .dollarDollarExpanded
        }
        if stated.empty, stated.rule == .entrypointKeepsImageCmd || stated.rule == .entrypointDropsImageCmd {
            truth.toggle()
            slip = .emptyEntrypointDropsCmd
        }
        if truth != stated.negated { return CommandFinding(claim: claim, outcome: .exact) }
        return CommandFinding(claim: claim, outcome: .wrong(slip), actual: Wording.rule(stated.rule, slip: slip))
    }

    /// Whether the service's process is a shell whose script expands the variable; `nil` when that is not known.
    func shellRuns(_ token: String, _ name: String?) -> Bool? {
        guard let name, let service = scene.project?.service(name),
              let process = ContainerProcess.of(service, image: scene.image(for: service), run: nil) else { return nil }
        if let shell = process.commandShellScript, Self.mentions(shell.script, Clause.variableName(token).name) {
            return true
        }
        return process.words == nil ? nil : false
    }

    func fileLine(_ claim: CommandClaim, service name: String, key: String, line: Int,
                  problem: FileProblem) -> CommandFinding {
        for file in scene.answerFiles {
            guard let service = file.service(name) else { continue }
            let found = FileChecks.problems(service, scene: scene)
            if let match = found.first(where: { $0.problem == problem && $0.setting.key == key
                && $0.setting.line == line }) {
                return CommandFinding(claim: claim, outcome: match.outcome, actual: match.explanation)
            }
        }
        return unchecked(claim, "the line is not in a compose file this answer shows")
    }
}
