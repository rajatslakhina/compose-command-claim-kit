/// A `docker compose run` command line: the service, a `--entrypoint` and the arguments after the service. Compose
/// splits `--entrypoint` into words (probed: `--entrypoint "/bin/sh -c"` is `/bin/sh` `-c`), unlike `docker run`.
public struct RunCommand: Sendable, Hashable {
    public let service: String
    /// `--entrypoint`, split; `[]` for `--entrypoint ""`; `nil` when not given.
    public let entrypoint: [String]?
    /// The words after the service: they replace the service's `command`.
    public let arguments: [String]
    /// The line as written.
    public let text: String

    public init(service: String, entrypoint: [String]?, arguments: [String], text: String) {
        self.service = service
        self.entrypoint = entrypoint
        self.arguments = arguments
        self.text = text
    }

    static let globalOptions: Set<String> = ["-f", "--file", "-p", "--project-name", "--env-file", "--profile",
                                             "--project-directory", "--ansi", "--progress", "--parallel"]
    static let valueOptions: Set<String> = ["-e", "--env", "--name", "-u", "--user", "-w", "--workdir", "-v",
                                            "--volume", "-p", "--publish", "-l", "--label", "--entrypoint", "--pull",
                                            "--cap-add", "--cap-drop", "--env-from-file"]
    static let flags: Set<String> = ["--rm", "-d", "--detach", "--no-deps", "-T", "--no-TTY", "--service-ports",
                                     "--use-aliases", "-i", "--interactive", "-t", "--tty", "--build", "--quiet-pull",
                                     "--remove-orphans", "-P", "--quiet-build", "-it", "-ti"]

    /// Reads `docker compose run ...` (or `docker-compose run ...`) from a line; `nil` when the line is not one or
    /// holds an option this reader does not know.
    public static func parse(_ line: String) -> RunCommand? {
        var words = StatedWords.split(line)
        if words.first == "$" || words.first == "sudo" { words.removeFirst() }
        if words.first == "docker", words.dropFirst().first == "compose" {
            words.removeFirst(2)
        } else if words.first == "docker-compose" {
            words.removeFirst()
        } else {
            return nil
        }
        guard let rest = skipGlobal(words), rest.first == "run" else { return nil }
        return runOptions(Array(rest.dropFirst()), text: line.trimmed)
    }

    static func skipGlobal(_ words: [String]) -> [String]? {
        var rest = ArraySlice(words)
        while let word = rest.first, word.hasPrefix("-") {
            let name = String(word.prefix { $0 != "=" })
            guard globalOptions.contains(name) else { return nil }
            rest.removeFirst()
            if !word.contains("=") { guard rest.popFirst() != nil else { return nil } }
        }
        return Array(rest)
    }

    static func runOptions(_ words: [String], text: String) -> RunCommand? {
        var rest = ArraySlice(words)
        var entrypoint: [String]?
        while let word = rest.first, word.hasPrefix("-") {
            rest.removeFirst()
            let name = String(word.prefix { $0 != "=" })
            if flags.contains(word) { continue }
            guard valueOptions.contains(name) else { return nil }
            let value: String
            if let equals = word.firstIndex(of: "=") {
                value = String(word[word.index(after: equals)...])
            } else {
                guard let next = rest.popFirst() else { return nil }
                value = next
            }
            if name == "--entrypoint" {
                guard let split = try? CommandWords.split(value), split.stop == nil else { return nil }
                entrypoint = split.words
            }
        }
        guard let service = rest.popFirst() else { return nil }
        return RunCommand(service: service, entrypoint: entrypoint, arguments: Array(rest), text: text)
    }
}

/// Words as a person types them on a command line or in prose: spaces separate them, quotes group and go, a
/// backslash keeps the next character. Operators stay words.
enum StatedWords {
    static func split(_ text: String) -> [String] {
        var words: [String] = []
        var buffer = ""
        var got = false
        var quote: Character?
        var escaped = false
        for character in text {
            if escaped {
                buffer.append(character)
                escaped = false
            } else if let open = quote {
                if character == open { quote = nil } else { buffer.append(character) }
            } else if character == "\\" {
                escaped = true
                got = true
            } else if character == "\"" || character == "'" {
                quote = character
                got = true
            } else if character.isWhitespace {
                if got { words.append(buffer) }
                buffer = ""
                got = false
            } else {
                buffer.append(character)
                got = true
            }
        }
        if got { words.append(buffer) }
        return words
    }

    /// The text with runs of white space made one space, for comparing scripts.
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
