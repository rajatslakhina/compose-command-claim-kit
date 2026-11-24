/// The words that state each rule. A clause states a rule when its topic is there, one of the rule's phrases is
/// there, and none of its excluded words is (`Dockerfile`, a healthcheck: other rules apply there).
struct RuleCue: Sendable {
    let rule: Rule
    let topic: @Sendable (Clause) -> Bool
    let phrases: [String]
    var excludes: [String] = []
}

enum RuleCues {
    static let keep = ["still runs", "still passed", "still appended", "is still", "are still", "keeps", "is kept",
                       "are kept", "preserves", "is preserved", "still applies", "still used", "still gets",
                       "remains", "is appended", "are appended", "still the default", "keeps running"]
    static let drop = ["drops", "is dropped", "ignores", "is ignored", "discards", "is discarded", "clears",
                       "is cleared", "resets", "is reset", "no longer", "throws away", "removes", "is removed",
                       "wipes", "is lost", "is not used", "isn't used", "stops running"]
    static let elsewhere = ["dockerfile", "healthcheck", "cmd instruction", "run instruction", "kubernetes", "pod",
                            "docker run ", "args:"]

    static let all: [RuleCue] = [
        RuleCue(rule: .stringRunsInShell, topic: { commandKey($0) && !writesShell($0) },
                phrases: ["through a shell", "in a shell", "via a shell", "by a shell", "with a shell",
                          "through /bin/sh", "via /bin/sh", "in /bin/sh", "through sh -c", "via sh -c",
                          "wrapped in /bin/sh", "wrapped in sh -c", "wraps it in /bin/sh", "wraps it in sh -c",
                          "wraps the string in", "a shell runs it", "the shell parses", "the shell interprets",
                          "interpreted by a shell", "interpreted by the shell", "parsed by a shell",
                          "parsed by the shell", "run by a shell", "run by the shell", "executed by a shell",
                          "executed by the shell", "executed in a shell", "executed through a shell",
                          "shell features work"],
                excludes: elsewhere + ["need", "needs", "must", "have to", "has to", "require", "requires",
                                       "differently", "unlike", "than", "like a", "like in", "as in a shell",
                                       "as a shell would", "shellwords", "go-shellwords"]),
        RuleCue(rule: .operatorPassedAsArgument, topic: operatorToken,
                phrases: ["as an argument", "as arguments", "as a literal", "passed literally", "taken literally",
                          "treated literally", "kept literally", "as plain text",
                          "as literal text", "as a string", "another argument", "an extra argument",
                          "a plain argument", "a literal argument"],
                // Inside a quoted script or a list item, `&&` is part of an argument: that is true.
                excludes: elsewhere + ["list form", "the list", "a list", "script", "quoted", "in quotes", "sh -c",
                                       "bash -c", "included", "as part of", "to sh", "to bash", "inside the string"]),
        RuleCue(rule: .operatorDropsRest, topic: operatorToken,
                phrases: ["is dropped", "are dropped", "gets dropped", "drops", "is ignored", "are ignored",
                          "gets ignored", "ignores", "is discarded", "discards", "cut off", "cuts off", "truncated",
                          "truncates", "stops reading", "stops at", "stops parsing", "everything after",
                          "is lost", "never runs", "never run", "thrown away", "throws away"],
                excludes: elsewhere),
        RuleCue(rule: .variablesFromContainer, topic: variableTopic,
                phrases: ["in the container", "inside the container", "at runtime", "at run time",
                          "when the container starts", "by the container", "from the container",
                          "container's environment", "from environment", "from the environment section",
                          "from the environment block", "from the environment key", "from the environment list",
                          "from the service's environment", "the environment: block", "the environment block",
                          "the environment section"],
                excludes: elsewhere + [".env", "your shell", "the shell", "host"]),
        RuleCue(rule: .variablesFromShell, topic: variableTopic,
                phrases: ["from your shell", "from the shell", "from the host", "on the host", "from .env",
                          "from the .env", "from a .env", "in your shell", "when compose reads",
                          "when it reads the file", "when compose parses", "when compose loads", "at parse time",
                          "before the container starts", "before the container runs", "when docker compose reads",
                          "when docker compose parses", "when the file is read", "when the file is parsed"],
                excludes: elsewhere),
        RuleCue(rule: .entrypointKeepsImageCmd, topic: { entrypointKey($0) && imageCmd($0) }, phrases: keep,
                excludes: ["--entrypoint", "docker run "]),
        RuleCue(rule: .entrypointDropsImageCmd, topic: { entrypointKey($0) && imageCmd($0) }, phrases: drop,
                excludes: ["--entrypoint", "docker run "]),
        RuleCue(rule: .commandReplacesEntrypoint, topic: { commandKey($0) && anyEntrypoint($0) },
                phrases: ["replaces the entrypoint", "replaces the image's entrypoint", "overrides the entrypoint",
                          "overrides the image's entrypoint", "bypasses the entrypoint", "skips the entrypoint",
                          "instead of the entrypoint", "replaces entrypoint", "overrides entrypoint",
                          "replaces its entrypoint", "overrides its entrypoint"],
                excludes: elsewhere + ["cmd", "--entrypoint"]),
        RuleCue(rule: .commandFollowsEntrypoint, topic: { commandKey($0) && anyEntrypoint($0) },
                phrases: ["appended to the entrypoint", "appended to the image's entrypoint",
                          "passed to the entrypoint", "passed to the image's entrypoint", "arguments to the entrypoint",
                          "arguments of the entrypoint", "args to the entrypoint", "after the entrypoint",
                          "appended to entrypoint", "passed to entrypoint", "handed to the entrypoint",
                          "given to the entrypoint", "arguments to its entrypoint", "passed to its entrypoint"],
                excludes: elsewhere + ["--entrypoint"]),
        RuleCue(rule: .runAppendsArguments, topic: runTopic,
                phrases: ["appended to", "appends", "added to the end", "added after", "after the service's command",
                          "in addition to the service's command", "on top of the service's command", "tacked on",
                          "added to the service's command", "extends the service's command"],
                excludes: ["entrypoint"]),
        RuleCue(rule: .runReplacesCommand, topic: runTopic,
                phrases: ["replace the service's command", "replaces the service's command",
                          "override the service's command", "overrides the service's command",
                          "instead of the service's command", "replace its command", "replaces its command",
                          "override its command", "overrides its command", "instead of its command",
                          "replace the command", "replaces the command", "override the command",
                          "overrides the command", "instead of the command"],
                excludes: ["entrypoint"]),
        RuleCue(rule: .runEntrypointKeepsCommand, topic: runEntrypointTopic, phrases: keep),
        RuleCue(rule: .runEntrypointDropsCommand, topic: runEntrypointTopic, phrases: drop),
        RuleCue(rule: .emptyCommandClears, topic: emptyCommand,
                phrases: ["runs nothing", "nothing runs", "no command runs", "has no command", "clears the image's",
                          "removes the image's", "drops the image's", "disables the image's", "clears the cmd",
                          "removes the cmd", "drops the cmd", "wipes the image's", "ignores the image's"]),
        RuleCue(rule: .emptyCommandFallsBack, topic: emptyCommand,
                phrases: ["falls back", "fall back", "the image's cmd runs", "uses the image's",
                          "image's default command", "the default cmd", "image's cmd is used", "keeps the image's"])
    ]

    static func commandKey(_ clause: Clause) -> Bool {
        clause.codes.contains { $0 == "command" || $0.hasPrefix("command:") }
            || Words.containsAny(clause.plain, ["the command string", "a string command", "command string",
                                                "the command key", "the command field", "compose command"])
    }

    /// The clause shows a command that starts a shell itself (`sh -c "cd /app && npm start"`).
    static func writesShell(_ clause: Clause) -> Bool {
        clause.codes.contains { code in
            let words = StatedWords.split(code.hasPrefix("command:") ? String(code.dropFirst(8)) : code)
            guard let flag = words.firstIndex(of: "-c"), flag > 0, flag + 1 < words.count else { return false }
            return ContainerProcess.shells.contains(ContainerProcess.basename(words[flag - 1]))
        }
    }

    static func entrypointKey(_ clause: Clause) -> Bool {
        clause.codes.contains { $0 == "entrypoint" || $0.hasPrefix("entrypoint:") }
            || Words.containsAny(clause.plain, ["the entrypoint key", "the entrypoint field", "compose entrypoint",
                                                "an entrypoint override", "overriding the entrypoint"])
    }

    static func anyEntrypoint(_ clause: Clause) -> Bool {
        Words.contains(clause.plain, "entrypoint")
    }

    static func imageCmd(_ clause: Clause) -> Bool {
        clause.codes.contains("CMD")
            || Words.containsAny(clause.plain, ["the image's cmd", "image's cmd", "its cmd", "the cmd",
                                                "default command", "image's command", "the image's default",
                                                "cmd from the image", "dockerfile's cmd"])
    }

    static func operatorToken(_ clause: Clause) -> Bool {
        clause.codes.contains { ["&&", "||", ";", "|", ">", ">>", "<", "&", "2>&1"].contains($0.trimmed) }
    }

    /// Words that say a variable is substituted, not merely set.
    static let expansions = ["expand", "expands", "expanded", "substitute", "substitutes", "substituted",
                             "interpolate", "interpolates", "interpolated", "resolve", "resolves", "resolved",
                             "replaced", "fill", "fills", "filled", "evaluated", "evaluates", "picked up",
                             "picks up", "read", "reads", "comes from", "come from", "taken from", "pulled from"]

    static func variableTopic(_ clause: Clause) -> Bool {
        let named = clause.variableToken != nil
            || (commandKey(clause) && Words.containsAny(clause.plain, ["variables", "variable"]))
        return named && Words.containsAny(clause.plain, expansions)
    }

    static func runTopic(_ clause: Clause) -> Bool {
        let named = Words.contains(clause.plain, "compose run") || clause.codes.contains { $0 == "run" }
        return named && Words.containsAny(clause.plain, ["arguments", "argument", "args", "command"])
    }

    static func runEntrypointTopic(_ clause: Clause) -> Bool {
        clause.plain.contains("--entrypoint") && Words.contains(clause.plain, "command")
    }

    static func emptyCommand(_ clause: Clause) -> Bool {
        clause.codes.contains { ["command: []", "command: \"\"", "command: ''"].contains($0) }
            || Words.containsAny(clause.plain, ["an empty command", "empty command"])
    }

    static func emptyEntrypoint(_ clause: Clause) -> Bool {
        clause.codes.contains { ["entrypoint: []", "entrypoint: \"\"", "entrypoint: ''"].contains($0) }
            || Words.containsAny(clause.plain, ["an empty entrypoint", "empty entrypoint"])
    }
}
