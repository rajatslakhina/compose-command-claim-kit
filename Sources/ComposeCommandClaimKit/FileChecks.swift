import EntrypointClaimKit

/// The `command:` and `entrypoint:` lines of a compose file that do not do what they look like, as compose reads
/// them: a string cut at `&&`, a string compose refuses, a `$VAR` meant to come from `environment:`, `sh -c` handed
/// its script in pieces, and a list item that is a whole command line.
enum FileChecks {
    struct Problem {
        let setting: CommandSetting
        let problem: FileProblem
        let outcome: CommandFinding.Outcome
        let explanation: String
    }

    static func claims(_ project: ComposeProject, scene: CommandScene) -> [CommandClaim] {
        project.services.flatMap { service in
            problems(service, scene: scene).map { claim(service, $0.setting, $0.problem) }
        }
    }

    static func claim(_ service: ComposeService, _ setting: CommandSetting, _ problem: FileProblem) -> CommandClaim {
        let shown: String
        switch setting.written {
        case let .string(text): shown = "\(setting.key): \(text)"
        case let .list(items): shown = "\(setting.key): [\(items.map(Wording.quoted).joined(separator: ", "))]"
        }
        return CommandClaim(kind: .fileLine(service: service.name, key: setting.key, line: setting.line,
                                            problem: problem), sentence: shown)
    }

    static func problems(_ service: ComposeService, scene: CommandScene) -> [Problem] {
        var found: [Problem] = []
        for setting in service.settings {
            let key = "`\(service.name)`'s `\(setting.key):`"
            if case let .refused(reason) = setting.reading {
                found.append(Problem(setting: setting, problem: .refused, outcome: .wrong(nil),
                                     explanation: "`docker compose` refuses this file: \(key) has \(reason) "
                                         + "(\"invalid command line string\")."))
            }
            if let stop = setting.stop, case let .words(words) = setting.reading,
               case let .string(text) = setting.written {
                found.append(Problem(setting: setting, problem: .truncated, outcome: .wrong(.stringRunsInShell),
                                     explanation: Wording.truncated(key, stop: stop, words: words, setting: setting.key,
                                                                    written: text)))
            }
            // `${PORT:-3000}` has a value either way: no caution for a name written with a default.
            let defaulted = Set(setting.writtenTexts.flatMap(Interpolation.defaultedNames(in:)))
            let names = setting.writtenTexts.flatMap(Interpolation.names(in:)).filter { !defaulted.contains($0) }
                .filter { name in
                    // `PASSWORD: ${PASSWORD}` passes the shell's value on: that is the shell's, as the command's is.
                    service.environment[name].map { !$0.contains("$") } == true
                        && setting.unknownVariables.contains(name)
                }
            if let name = names.first {
                found.append(Problem(setting: setting, problem: .environmentVariable,
                                     outcome: .caveat(.variableFromShell),
                                     explanation: Wording.environmentLine(key, name: name)))
            }
        }
        guard let process = ContainerProcess.of(service, image: scene.image(for: service), run: nil),
              let words = process.words else { return found }
        if let shell = process.shellScript, !shell.rest.isEmpty, !shell.script.contains(" "),
           !shell.script.contains("$"), let setting = service.command ?? service.entrypoint {
            found.append(Problem(setting: setting, problem: .splitScript, outcome: .wrong(.scriptTakesFollowingWords),
                                 explanation: Wording.splitScript(service.name, words: words, script: shell.script,
                                                                  rest: shell.rest)))
        }
        if let first = words.first, first.contains(" "), let setting = listOrigin(service, process) {
            found.append(Problem(setting: setting, problem: .programWithSpaces, outcome: .wrong(.listItemSplit),
                                 explanation: Wording.programWithSpaces(service.name, program: first)))
        }
        return found
    }

    /// The list setting the program comes from: `entrypoint:` when it is set and not empty, else `command:` when
    /// the entrypoint is empty.
    static func listOrigin(_ service: ComposeService, _ process: ContainerProcess) -> CommandSetting? {
        if let entrypoint = service.entrypoint, entrypoint.words?.isEmpty == false {
            return entrypoint.isList ? entrypoint : nil
        }
        guard let command = service.command, command.isList, process.entrypoint == [] else { return nil }
        return command
    }
}

extension CommandSetting {
    var isList: Bool {
        if case .list = written { return true }
        return false
    }
}
