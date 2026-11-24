/// Something an answer says about what a compose service runs, or about the rules compose follows to get there.
public struct CommandClaim: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// "`web` runs `npm run dev`": the process a service's container starts, for `docker compose up` or for
        /// the `docker compose run` line the sentence names.
        case runs(service: String?, stated: String, run: RunCommand?)
        /// "`$GREETING` becomes `hi`": what a variable in a service's command turns into.
        case variable(service: String?, token: String, stated: String)
        /// A rule of how compose reads `command:` and `entrypoint:`, stated or denied. `token` is the variable the
        /// sentence names (`$HOME`, `$$HOME`); `emptyValue` marks an empty `entrypoint:` or `command:`.
        case rule(Rule, negated: Bool, token: String?, service: String?, emptyValue: Bool)
        /// A `command:` or `entrypoint:` line of a compose file the answer shows.
        case fileLine(service: String, key: String, line: Int, problem: FileProblem)
    }

    public let kind: Kind
    /// The sentence the claim was read from, or the file line.
    public let sentence: String

    public init(kind: Kind, sentence: String) {
        self.kind = kind
        self.sentence = sentence
    }
}

/// What is wrong with a `command:` or `entrypoint:` line, as compose reads it.
public enum FileProblem: String, Sendable, Hashable, CaseIterable {
    /// A string with `&&`, `;`, `|`, `<` or `>` outside quotes: compose stops there and drops the rest.
    case truncated
    /// A string `docker compose` refuses ("invalid command line string").
    case refused
    /// A `$VAR` the service sets only in `environment:`: compose substitutes it from the shell or `.env`.
    case environmentVariable
    /// `sh -c` followed by several words: only the first is the script.
    case splitScript
    /// A list item with spaces as the program: it is one word, not a command line.
    case programWithSpaces
}

/// A rule of how compose reads `command:` and `entrypoint:` that answers state, true or false.
public enum Rule: String, Sendable, Hashable, CaseIterable {
    /// "A string `command` runs through a shell." False.
    case stringRunsInShell
    /// "`&&` is passed to the program as an argument." False.
    case operatorPassedAsArgument
    /// "Compose drops everything from `&&` on." True.
    case operatorDropsRest
    /// "`$VAR` in `command` is expanded in the container (from `environment:`)." False for `$VAR`; for `$$VAR`,
    /// true only when the command runs a shell.
    case variablesFromContainer
    /// "Compose fills `$VAR` from your shell or `.env` when it reads the file." True for `$VAR`, false for `$$VAR`.
    case variablesFromShell
    /// "Setting `entrypoint` keeps the image's CMD." False (true for an empty `entrypoint`).
    case entrypointKeepsImageCmd
    /// "Setting `entrypoint` drops the image's CMD." True (false for an empty `entrypoint`).
    case entrypointDropsImageCmd
    /// "`command` replaces the image's ENTRYPOINT." False.
    case commandReplacesEntrypoint
    /// "`command` is passed to the image's ENTRYPOINT as arguments." True.
    case commandFollowsEntrypoint
    /// "`docker compose run` appends its arguments to the service's command." False.
    case runAppendsArguments
    /// "`docker compose run` arguments replace the service's command." True.
    case runReplacesCommand
    /// "`docker compose run --entrypoint` keeps the service's command." False.
    case runEntrypointKeepsCommand
    /// "`docker compose run --entrypoint` drops the service's command." True.
    case runEntrypointDropsCommand
    /// "An empty `command` runs nothing (clears the image's CMD)." False.
    case emptyCommandClears
    /// "An empty `command` falls back to the image's CMD." True.
    case emptyCommandFallsBack

    /// Whether compose works this way (for a plain `$VAR` and a non-empty `entrypoint`).
    public var isTrue: Bool {
        switch self {
        case .operatorDropsRest, .variablesFromShell, .entrypointDropsImageCmd, .commandFollowsEntrypoint,
             .runReplacesCommand, .runEntrypointDropsCommand, .emptyCommandFallsBack: true
        default: false
        }
    }

    /// The mistake that believing the wrong side of this rule shows.
    public var slip: CommandFinding.Slip {
        switch self {
        case .stringRunsInShell: .stringRunsInShell
        case .operatorPassedAsArgument, .operatorDropsRest: .operatorBecomesArgument
        case .variablesFromContainer, .variablesFromShell: .variableReadInContainer
        case .entrypointKeepsImageCmd, .entrypointDropsImageCmd: .entrypointKeepsImageCmd
        case .commandReplacesEntrypoint, .commandFollowsEntrypoint: .commandReplacesEntrypoint
        case .runAppendsArguments, .runReplacesCommand: .runAppendsToCommand
        case .runEntrypointKeepsCommand, .runEntrypointDropsCommand: .runEntrypointKeepsCommand
        case .emptyCommandClears, .emptyCommandFallsBack: .emptyCommandClears
        }
    }
}
