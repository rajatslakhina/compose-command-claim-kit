import EntrypointClaimKit

/// The processes compose would start if it worked the way a recognisable mistake says. A stated command line that
/// differs from what compose starts is wrong only when one of these reproduces it.
enum Misreadings {
    struct Alternative {
        let slip: CommandFinding.Slip
        let process: ContainerProcess
        /// What compose does instead, after "`web` runs `...`: ".
        let reason: String
    }

    static func alternatives(_ service: ComposeService, image: ImageCommands?, run: RunCommand?,
                             actual: ContainerProcess, variables: Variables) -> [Alternative] {
        var found: [Alternative] = []
        let runsAsWritten = run == nil || (run?.entrypoint == nil && run?.arguments.isEmpty == true)
        let effective = [run?.entrypoint == nil ? service.entrypoint : nil, runsAsWritten ? service.command : nil]
        for setting in effective.compactMap({ $0 }) {
            if let shell = setting.shellReading, let stop = setting.stop,
               let process = replacing(setting, with: shell, service, image, run) {
                found.append(Alternative(slip: .stringRunsInShell, process: process,
                                         reason: "compose runs no shell for a `\(setting.key):` string; it splits "
                                             + "the string into words and stops at `\(stop.mark)`, dropping "
                                             + "`\(stop.dropped)`."))
            }
            if let split = setting.splitItems, let process = replacing(setting, with: split, service, image, run) {
                found.append(Alternative(slip: .listItemSplit, process: process,
                                         reason: "one list item is one word; an item with spaces is not split."))
            }
        }
        found += images(service, image: image, run: run, actual: actual)
        found += runs(service, image: image, run: run)
        if let shell = actual.shellScript, !shell.rest.isEmpty, let words = actual.words {
            let joined = ([shell.script] + shell.rest).joined(separator: " ")
            found.append(Alternative(slip: .scriptTakesFollowingWords,
                                     process: ContainerProcess(entrypoint: [], command: [words[0], "-c", joined]),
                                     reason: "`-c` takes only the next word as the script; the words after it fill "
                                         + "`$0`, `$1`, ..."))
        }
        found += variableReadings(service, image: image, run: run, actual: actual, variables: variables)
        return found
    }

    /// Mistakes about the image's ENTRYPOINT and CMD.
    static func images(_ service: ComposeService, image: ImageCommands?, run: RunCommand?,
                       actual: ContainerProcess) -> [Alternative] {
        guard let image else { return [] }
        var found: [Alternative] = []
        let entrypoint = entrypointInEffect(service, run)
        if let entrypoint, !entrypoint.isEmpty, commandInEffect(service, run).isEmpty, let cmd = image.cmd.words,
           !cmd.isEmpty {
            found.append(Alternative(slip: .entrypointKeepsImageCmd,
                                     process: ContainerProcess(entrypoint: entrypoint, command: cmd),
                                     reason: "an entrypoint set in compose drops the image's CMD "
                                         + "(`\(Wording.line(cmd))`)."))
        }
        if entrypoint == nil, image.entrypointIsShellForm, let words = image.entrypoint.words, words.count >= 3,
           let command = actual.command, !command.isEmpty {
            let reason = "the image's ENTRYPOINT is in shell form, so it ignores the command; "
                + "`\(Wording.line(command))` only fills `$0`, `$1`, ..."
            found.append(Alternative(slip: .shellEntrypointTakesCommand,
                                     process: ContainerProcess(entrypoint: [], command: [
                                         words[0], words[1], ([words[2]] + command).joined(separator: " ")
                                     ]), reason: reason))
            found.append(Alternative(slip: .commandReplacesEntrypoint,
                                     process: ContainerProcess(entrypoint: [], command: command), reason: reason))
        }
        return found
    }

    /// Mistakes about `docker compose run`.
    static func runs(_ service: ComposeService, image: ImageCommands?, run: RunCommand?) -> [Alternative] {
        guard let run, let command = service.command?.words, !command.isEmpty else { return [] }
        if let entrypoint = run.entrypoint {
            guard !entrypoint.isEmpty, run.arguments.isEmpty else { return [] }
            return [Alternative(slip: .runEntrypointKeepsCommand,
                                process: ContainerProcess(entrypoint: entrypoint, command: command),
                                reason: "`--entrypoint` drops the service's `command:`.")]
        }
        guard !run.arguments.isEmpty else { return [] }
        let process = ContainerProcess.start(entrypoint: service.entrypoint?.words, command: command + run.arguments,
                                             image: image)
        return [Alternative(slip: .runAppendsToCommand, process: process,
                            reason: "the arguments after the service replace its `command:`; they are not added "
                                + "to it.")]
    }

    /// Mistakes about where variables come from.
    static func variableReadings(_ service: ComposeService, image: ImageCommands?, run: RunCommand?,
                                 actual: ContainerProcess, variables: Variables) -> [Alternative] {
        var found: [Alternative] = []
        let substituted = service.substitutedNames.filter { service.environment[$0] != nil }
        if !substituted.isEmpty {
            let believed = service.reread(variables.reading(environment: service.environment))
            if let process = ContainerProcess.of(believed, image: image, run: run), process != actual {
                found.append(Alternative(slip: .variableReadInContainer, process: process,
                                         reason: "compose fills `$\(substituted[0])` from your shell or `.env` when "
                                             + "it reads the file, not from the service's `environment:`."))
            }
        }
        let values = service.escapedNames.compactMap { name in service.environment[name].map { (name, $0) } }
        if let first = values.first, actual.shellScript == nil, let words = actual.words {
            let expanded = words.map { word in
                values.reduce(word) { text, pair in
                    text.replacingOccurrences(of: "${\(pair.0)}", with: pair.1)
                        .replacingOccurrences(of: "$\(pair.0)", with: pair.1)
                }
            }
            found.append(Alternative(slip: .dollarDollarExpanded,
                                     process: ContainerProcess(entrypoint: [], command: expanded),
                                     reason: "`$$` passes a literal `$` to the container, and no shell runs the "
                                         + "command to expand `$\(first.0)`."))
        }
        return found
    }

    /// The entrypoint the daemon gets: `run --entrypoint`, else the service's.
    static func entrypointInEffect(_ service: ComposeService, _ run: RunCommand?) -> [String]? {
        if let override = run?.entrypoint { return override }
        return service.entrypoint?.words
    }

    /// The command the daemon gets: `run`'s arguments, else the service's (dropped by `run --entrypoint`).
    static func commandInEffect(_ service: ComposeService, _ run: RunCommand?) -> [String] {
        if let run, !run.arguments.isEmpty { return run.arguments }
        if run?.entrypoint != nil { return [] }
        if let words = service.command?.words { return words }
        return []
    }

    static func replacing(_ setting: CommandSetting, with words: [String], _ service: ComposeService,
                          _ image: ImageCommands?, _ run: RunCommand?) -> ContainerProcess? {
        var copy = service
        if setting.key == "entrypoint" {
            copy.entrypoint = CommandSetting(replacing: setting, words: words)
        } else {
            copy.command = CommandSetting(replacing: setting, words: words)
        }
        return ContainerProcess.of(copy, image: image, run: run)
    }

    /// The claim names the command, and the image's exec-form ENTRYPOINT (not a wrapper that hands it on) comes
    /// first: it holds as the command, with a note.
    static func entrypointPrefix(_ service: ComposeService, image: ImageCommands?, run: RunCommand?,
                                 actual: ContainerProcess, stated: [String]) -> Bool {
        guard service.entrypoint == nil, run?.entrypoint == nil, let image, !image.entrypointIsShellForm,
              let entrypoint = image.entrypoint.words, !entrypoint.isEmpty else { return false }
        return stated == actual.command && !ContainerProcess.handsOn(entrypoint)
    }
}
