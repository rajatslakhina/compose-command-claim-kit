/// How Compose turns a `command:` or `entrypoint:` string into words. Compose runs no shell: it splits the string
/// with go-shellwords (no variable or backtick expansion). The rules below are the ones probed against
/// `docker compose config` (Docker Compose 2.32.4):
/// - Spaces, tabs and newlines separate words. Single quotes keep their text literal. Double quotes keep spaces,
///   and a backslash in them takes the next character literally (`"e\nf"` is `enf`); outside quotes a backslash
///   does the same (`a\ b` is one word).
/// - `$`, `~`, `*`, `#` and `!` stay as typed. `$(...)` is one literal word, spaces and `;` included.
/// - At an unquoted `;`, `&`, `|`, `<` or `>`, compose stops reading and drops the rest, unread: `cd /app && npm
///   start` is `cd /app`. A word starting with a digit right before `>` (`2>&1`) is dropped with it.
/// - An unquoted `(` or `)` outside `$(...)`, an unclosed quote or `$(`, and a trailing backslash make
///   `docker compose` refuse the file: "invalid command line string".
/// - In backticks, spaces and operators stay in the word and quotes are removed; any other shape in backticks
///   was not probed and is left unfollowed.
enum CommandWords {
    struct Split: Hashable, Sendable {
        var words: [String]
        /// Where compose stopped reading.
        var stop: Stop?
    }

    struct Stop: Hashable, Sendable {
        /// The operator compose stopped at (`&&`, `;`, `|`, `>`, `2>&1`).
        let mark: String
        /// The text compose drops, from the operator (or the dropped digit word) on.
        let dropped: String
    }

    enum Failure: Error, Equatable {
        /// `docker compose` refuses the file.
        case refused(String)
        /// A shape the probes did not cover.
        case unfollowed(String)
    }

    static let invalid = "an unquoted `(` or `)`, an unclosed quote or a trailing backslash"

    static func split(_ text: String) throws(Failure) -> Split {
        var scanner = Scanner(characters: Array(text))
        return try scanner.run()
    }

    struct Scanner {
        let characters: [Character]
        var words: [String] = []
        var buffer = ""
        var got = false
        var escaped = false
        var single = false
        var double = false
        var dollar = false
        var backtick = false

        init(characters: [Character]) {
            self.characters = characters
        }

        mutating func run() throws(Failure) -> Split {
            for (index, character) in characters.enumerated() {
                if let stop = try step(character, at: index) { return Split(words: words, stop: stop) }
            }
            if escaped || single || double || dollar { throw .refused(CommandWords.invalid) }
            if backtick { throw .unfollowed("an unclosed backtick") }
            if got { words.append(buffer) }
            return Split(words: words, stop: nil)
        }

        /// Reads one character; returns where compose stops, if it stops here.
        mutating func step(_ character: Character, at index: Int) throws(Failure) -> Stop? {
            if escaped {
                buffer.append(character)
                escaped = false
                got = true
                return nil
            }
            if dollar {
                if character == "(" { throw .refused(CommandWords.invalid) }
                buffer.append(character)
                if character == ")" { dollar = false }
                return nil
            }
            if character == "\\" {
                try backslash()
                return nil
            }
            if try quoted(character) { return nil }
            return try bare(character, at: index)
        }

        mutating func backslash() throws(Failure) {
            if backtick { throw .unfollowed("a backslash in backticks") }
            if single { buffer.append("\\") } else { escaped = true }
            got = true
        }

        /// A quote, or a character inside quotes or backticks; `false` when the character is bare.
        mutating func quoted(_ character: Character) throws(Failure) -> Bool {
            switch character {
            case "'" where !double:
                single.toggle()
                got = true
            case "\"" where !single:
                double.toggle()
                got = true
            case _ where single || double:
                buffer.append(character)
            case "`":
                backtick.toggle()
                buffer.append(character)
                got = true
            case "(" where backtick, ")" where backtick:
                throw .unfollowed("a parenthesis in backticks")
            case _ where backtick:
                buffer.append(character)
            default:
                return false
            }
            return true
        }

        /// A character outside quotes.
        mutating func bare(_ character: Character, at index: Int) throws(Failure) -> Stop? {
            switch character {
            case " ", "\t", "\n", "\r":
                if got { words.append(buffer) }
                buffer = ""
                got = false
            case "(":
                guard buffer.last == "$" else { throw .refused(CommandWords.invalid) }
                buffer.append(character)
                dollar = true
            case ")":
                throw .refused(CommandWords.invalid)
            case ";", "&", "|", "<", ">":
                return stop(at: index)
            default:
                buffer.append(character)
                got = true
            }
            return nil
        }

        mutating func stop(at index: Int) -> Stop {
            let operators: Set<Character> = [";", "&", "|", "<", ">"]
            let markEnd = characters[index...].firstIndex { !operators.contains($0) } ?? characters.count
            var start = index
            if characters[index] == ">", buffer.first?.isNumber == true {
                start = index - buffer.count
                let digits = String(buffer)
                buffer = ""
                return Stop(mark: digits + String(characters[index..<markEnd]) + tail(after: markEnd),
                            dropped: String(characters[start...]))
            }
            if got { words.append(buffer) }
            return Stop(mark: String(characters[index..<markEnd]) + tail(after: markEnd),
                        dropped: String(characters[start...]))
        }

        /// `2>&1`: the descriptor after `>&` belongs to the operator.
        func tail(after end: Int) -> String {
            guard end > 0, characters[end - 1] == "&" else { return "" }
            return String(characters[end...].prefix { $0.isNumber })
        }
    }
}
