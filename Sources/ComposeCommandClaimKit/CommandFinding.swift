/// What a claim about a compose service's command turned out to be once compose's reading of the file was applied.
public struct CommandFinding: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        case exact
        /// Holds, with something a reader should know.
        case caveat(Caveat)
        case wrong(Slip?)
        /// Could not be checked, and why.
        case unchecked(String)
    }

    public enum Caveat: String, Sendable, Hashable, CaseIterable {
        /// The stated value holds only if the shell running `docker compose` (or `.env`) sets the variable to it:
        /// compose never substitutes from the service's `environment:`.
        case variableFromShell
        /// The claim names the command, and the image's ENTRYPOINT comes before it.
        case entrypointPrefix
    }

    /// A recognisable mistake about how compose starts a service.
    public enum Slip: String, Sendable, Hashable, CaseIterable {
        /// A `command:` string read as run through `/bin/sh -c`: compose splits it into words with no shell.
        case stringRunsInShell
        /// `&&`, `;`, `|` or `>` read as passed to the program as arguments: compose stops there and drops the rest.
        case operatorBecomesArgument
        /// `$VAR` read as the container's (or `environment:`'s) value: compose fills it from the shell or `.env`.
        case variableReadInContainer
        /// `$$VAR` read as expanded although no shell runs the command: the container gets a literal `$VAR`.
        case dollarDollarExpanded
        /// A list item with spaces read as several words: one item is one word.
        case listItemSplit
        /// A compose `entrypoint:` read as keeping the image's CMD: it drops it.
        case entrypointKeepsImageCmd
        /// An empty `entrypoint:` read as dropping the image's CMD: it keeps it.
        case emptyEntrypointDropsCmd
        /// `command:` read as replacing the image's ENTRYPOINT: it is passed to it (or ignored by a shell form).
        case commandReplacesEntrypoint
        /// An empty `command:` read as running nothing: the image's CMD runs.
        case emptyCommandClears
        /// `docker compose run svc args` read as adding the arguments to the service's command: they replace it.
        case runAppendsToCommand
        /// `docker compose run --entrypoint` read as keeping the service's command: it drops it.
        case runEntrypointKeepsCommand
        /// `sh -c` read as taking every following word as its script: it takes only the first.
        case scriptTakesFollowingWords
        /// A shell-form ENTRYPOINT read as receiving the command: it ignores it.
        case shellEntrypointTakesCommand
    }

    public enum Severity: Int, Sendable, Hashable, Comparable {
        case holds
        case unchecked
        case caution
        case wrong

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let claim: CommandClaim
    public let outcome: Outcome
    let detail: String
    /// Flagged in an earlier review of the same conversation (set by `CommandLedger`).
    public internal(set) var isRepeated = false

    init(claim: CommandClaim, outcome: Outcome, actual: String = "") {
        self.claim = claim
        self.outcome = outcome
        detail = actual
    }

    /// What compose actually does, in words, where the claim gets it wrong or needs a note.
    public var actual: String? {
        detail.isEmpty ? nil : detail
    }

    public var severity: Severity {
        switch outcome {
        case .exact: .holds
        case .unchecked: .unchecked
        case .caveat: .caution
        case .wrong: .wrong
        }
    }

    public var slip: Slip? {
        if case let .wrong(slip) = outcome { return slip }
        return nil
    }

    /// One sentence for a note: what compose does, or why the claim was not checked.
    public var explanation: String {
        switch outcome {
        case .exact: "Holds."
        case let .unchecked(reason): "Not checked: \(reason)."
        case .caveat, .wrong: detail
        }
    }
}
