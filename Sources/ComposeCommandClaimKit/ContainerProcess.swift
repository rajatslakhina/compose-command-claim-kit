import EntrypointClaimKit

/// What a service's container executes: the entrypoint words, then the command words. Built with the daemon's
/// rules (probed with `docker compose create` and `docker inspect`): a non-empty entrypoint from compose drops the
/// image's CMD; an empty one (`entrypoint: ""` or `[]`) clears the image's ENTRYPOINT but keeps its CMD; an empty
/// command (`command: []` or `""`) falls back to the image's CMD.
public struct ContainerProcess: Sendable, Hashable {
    /// The entrypoint words in effect; `nil` when the image's entrypoint, unseen, comes first.
    public let entrypoint: [String]?
    /// The command words in effect; `nil` when they are the image's CMD and the image is unseen.
    public let command: [String]?

    public init(entrypoint: [String]?, command: [String]?) {
        self.entrypoint = entrypoint
        self.command = command
    }

    /// Every word, when both parts are known.
    public var words: [String]? {
        guard let entrypoint, let command else { return nil }
        return entrypoint + command
    }

    /// The daemon refuses to start the container: "no command specified".
    public var isRefused: Bool {
        words?.isEmpty == true
    }

    /// For a process started as `sh -c "script"`: the script, and the words after it (they fill `$0`, `$1`, ...).
    var shellScript: (script: String, rest: [String])? {
        guard let words, let first = words.first, Self.shells.contains(Self.basename(first)),
              words.count >= 3, words[1] == "-c" else { return nil }
        return (words[2], Array(words.dropFirst(3)))
    }

    /// The shell script, also when the image's unseen entrypoint comes first and the command itself starts a shell.
    var commandShellScript: (script: String, rest: [String])? {
        shellScript ?? command.flatMap { ContainerProcess(entrypoint: [], command: $0).shellScript }
    }

    static let shells: Set<String> = ["sh", "bash", "dash", "ash", "zsh"]

    static func basename(_ word: String) -> String {
        String(word.reversed().prefix { $0 != "/" }.reversed())
    }

    /// Whether the entrypoint hands the command on unchanged: it ends in `--`, it is an init such as `tini`, or it
    /// is a lone script (`*.sh`, or named like an entrypoint). A claim naming the command then holds.
    static func handsOn(_ entrypoint: [String]) -> Bool {
        guard let first = entrypoint.first else { return true }
        let name = basename(first).lowercased()
        if entrypoint.last == "--" || ["tini", "tini-static", "dumb-init", "catatonit"].contains(name) { return true }
        return entrypoint.count == 1 && (name.hasSuffix(".sh") || name.contains("entrypoint"))
    }

    /// The process from the user's entrypoint and command (`nil`: not set) and the image's config (`nil`: unseen).
    static func start(entrypoint: [String]?, command: [String]?, image: ImageCommands?) -> ContainerProcess {
        let given = command ?? []
        if let entrypoint, !entrypoint.isEmpty { return ContainerProcess(entrypoint: entrypoint, command: given) }
        let tail = given.isEmpty ? image?.cmd.words : given
        if entrypoint != nil { return ContainerProcess(entrypoint: [], command: tail) }
        return ContainerProcess(entrypoint: image?.entrypoint.words, command: tail)
    }

    /// The process for `docker compose up` (no `run`) or for a `run` line.
    static func of(_ service: ComposeService, image: ImageCommands?, run: RunCommand?) -> ContainerProcess? {
        let setEntrypoint: [String]?
        if let setting = service.entrypoint {
            guard let words = setting.words else { return nil }
            setEntrypoint = words
        } else {
            setEntrypoint = nil
        }
        let setCommand: [String]?
        if let setting = service.command {
            guard let words = setting.words else { return nil }
            setCommand = words
        } else {
            setCommand = nil
        }
        guard let run else { return start(entrypoint: setEntrypoint, command: setCommand, image: image) }
        if let override = run.entrypoint {
            return start(entrypoint: override, command: run.arguments.isEmpty ? nil : run.arguments, image: image)
        }
        return start(entrypoint: setEntrypoint, command: run.arguments.isEmpty ? setCommand : run.arguments,
                     image: image)
    }

    enum Match: Equatable {
        case yes
        case no
        /// The unseen image entrypoint could make it true.
        case possible
    }

    /// Whether a stated command line names this process: every word, the command an entrypoint wrapper hands on, or
    /// the script a shell runs.
    func matches(words stated: [String], text: String) -> Match {
        let script = StatedWords.normalized(text)
        if let words {
            if stated == words { return .yes }
            if let entrypoint, let command, stated == command, !command.isEmpty, Self.handsOn(entrypoint) {
                return .yes
            }
            if let shell = shellScript, StatedWords.normalized(shell.script) == script, shell.rest.isEmpty {
                return .yes
            }
            return .no
        }
        guard let command else { return .possible }
        if stated == command, !command.isEmpty { return .yes }
        if let shell = ContainerProcess(entrypoint: [], command: command).shellScript,
           StatedWords.normalized(shell.script) == script, shell.rest.isEmpty {
            return .yes
        }
        if stated.count > command.count, Array(stated.suffix(command.count)) == command { return .possible }
        return .no
    }

    /// The command line as a person would type it.
    public var display: String? {
        words.map { Launch(words: $0, prefixFromBase: false).display }
    }
}
