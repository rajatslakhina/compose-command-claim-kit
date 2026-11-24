import EntrypointClaimKit

/// The sentences findings use.
enum Wording {
    /// A command line as a person would type it.
    static func line(_ words: [String]) -> String {
        Launch(words: words, prefixFromBase: false).display
    }

    static func quoted(_ word: String) -> String {
        "\"" + word.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// A list for a compose file: `["sh", "-c", "cd /app && npm start"]`.
    static func list(_ words: [String]) -> String {
        "[" + words.map(quoted).joined(separator: ", ") + "]"
    }

    static func process(_ process: ContainerProcess) -> String {
        if let words = process.words {
            return words.isEmpty ? "nothing (the daemon refuses with \"no command specified\")" : "`\(line(words))`"
        }
        if let command = process.command { return "the image's ENTRYPOINT, then `\(line(command))`" }
        return "the image's ENTRYPOINT and CMD"
    }

    static func runs(_ alternative: Misreadings.Alternative, service: ComposeService, actual: ContainerProcess,
                     run: RunCommand?) -> String {
        let subject = run.map { "`\($0.text)`" } ?? "`\(service.name)`"
        return "\(subject) runs \(process(actual)): \(alternative.reason)"
    }

    static func truncated(_ key: String, stop: CommandWords.Stop, words: [String], setting: String,
                          written: String) -> String {
        "\(key) runs no shell: compose splits it into words and stops at `\(stop.mark)`, dropping "
            + "`\(stop.dropped.trimmed)`, so the command is `\(line(words))`. To run all of it, start a shell: "
            + "`\(setting): \(list(["sh", "-c", written.trimmed]))`."
    }

    static func environmentLine(_ key: String, name: String) -> String {
        "\(key) uses `$\(name)`, which compose fills from your shell or `.env` when it reads the file, not from "
            + "the service's `environment:`; unless one of them sets it, the value is empty. For the container's "
            + "value, write `$$\(name)` and run the command through `sh -c`."
    }

    static func splitScript(_ service: String, words: [String], script: String, rest: [String]) -> String {
        "`\(service)` runs `\(line(words))`: `-c` takes only `\(script)` as the script, and `\(line(rest))` "
            + "only fills `$0`, `$1`, .... Put the script in one word: "
            + "`\(list(Array(words.prefix(2)) + [([script] + rest).joined(separator: " ")]))`."
    }

    static func programWithSpaces(_ service: String, program: String) -> String {
        let split = program.split(whereSeparator: \.isWhitespace).map(String.init)
        return "`\(service)` runs a program named `\(program)`: a list item is one word. Give each word its own "
            + "item: `\(list(split))`."
    }

    static func prefixed(_ service: ComposeService, _ actual: ContainerProcess) -> String {
        "`\(service.name)` runs \(process(actual)): the claim names the command, and the image's ENTRYPOINT "
            + "comes before it."
    }

    static func fromShell(_ service: ComposeService, names: [String], unset: ContainerProcess?) -> String {
        let listed = names.map { "`$\($0)`" }.joined(separator: ", ")
        let otherwise = unset.map { " With nothing set, it runs \(process($0))." } ?? ""
        return "This holds only if your shell or `.env` sets \(listed) the same way: compose fills them when it "
            + "reads the file and never reads `\(service.name)`'s `environment:`.\(otherwise)"
    }

    static func rule(_ rule: Rule, slip: CommandFinding.Slip?) -> String {
        if slip == .dollarDollarExpanded {
            return "`$$NAME` reaches the container as a literal `$NAME`: compose does not substitute it, and only a "
                + "shell started in the container (`sh -c`) expands it."
        }
        if slip == .emptyEntrypointDropsCmd {
            return "An empty `entrypoint:` (`\"\"` or `[]`) clears the image's ENTRYPOINT but keeps its CMD, which "
                + "then runs on its own."
        }
        switch rule {
        case .stringRunsInShell:
            return "Compose runs no shell for a `command:` or `entrypoint:` string: it splits the string into words "
                + "and stops at the first unquoted `;`, `&`, `|`, `<` or `>`. Shell features need `sh -c`."
        case .operatorPassedAsArgument, .operatorDropsRest:
            return "Compose does not pass `&&` (or `;`, `|`, `>`) to the program: it stops reading the string there "
                + "and drops the rest."
        case .variablesFromContainer, .variablesFromShell:
            return "Compose substitutes `$NAME` in `command:` when it reads the file, from the shell running "
                + "`docker compose` and `.env`; the service's `environment:` is not used. `$$NAME` passes a literal "
                + "`$NAME` for a shell in the container."
        case .entrypointKeepsImageCmd, .entrypointDropsImageCmd:
            return "Setting `entrypoint:` in compose drops the image's CMD; only `command:` gives the new "
                + "entrypoint arguments."
        case .commandReplacesEntrypoint, .commandFollowsEntrypoint:
            return "`command:` replaces only the image's CMD: it is passed to the image's ENTRYPOINT as arguments "
                + "(and a shell-form ENTRYPOINT ignores it)."
        case .runAppendsArguments, .runReplacesCommand:
            return "The arguments after the service in `docker compose run` replace its `command:`; they are not "
                + "added to it."
        case .runEntrypointKeepsCommand, .runEntrypointDropsCommand:
            return "`docker compose run --entrypoint` drops the service's `command:`; arguments after the service "
                + "become the new command."
        case .emptyCommandClears, .emptyCommandFallsBack:
            return "An empty `command:` (`[]` or `\"\"`) clears nothing: the image's CMD runs."
        }
    }
}
