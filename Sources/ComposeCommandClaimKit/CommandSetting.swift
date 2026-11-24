/// A service's `command:` or `entrypoint:` as compose reads it: substituted, then split (a string) or taken item by
/// item (a list).
public struct CommandSetting: Sendable, Hashable {
    public enum Written: Sendable, Hashable {
        /// A string: compose splits it into words, with no shell.
        case string(String)
        /// A list: each item is one word.
        case list([String])
    }

    public enum Reading: Sendable, Hashable {
        /// The words compose sends to the daemon.
        case words([String])
        /// `docker compose` refuses the file, and why.
        case refused(String)
        /// A shape this reader does not follow, and what it is.
        case unfollowed(String)
    }

    /// `command` or `entrypoint`.
    public let key: String
    public let written: Written
    /// The line of the compose file the key is on.
    public let line: Int
    public let reading: Reading
    /// Names substituted that the conversation does not set: compose fills them from the shell, which is unseen.
    public let unknownVariables: Set<String>
    /// For a string: where compose stopped reading it.
    let stop: CommandWords.Stop?
    /// For a string: the text after substitution, as a shell would have been handed it.
    let substituted: String?

    init(key: String, node: ComposeNode, line: Int, variables: Variables) {
        self.key = key
        self.line = line
        var unknown: Set<String> = []
        var stop: CommandWords.Stop?
        var substituted: String?
        let written: Written
        let reading: Reading
        switch node {
        case let .scalar(text):
            written = .string(text)
            let string = Self.readString(text, variables)
            reading = string.reading
            unknown = string.unknown
            stop = string.stop
            substituted = string.substituted
        case let .list(items):
            let texts = items.compactMap(\.text)
            written = .list(texts)
            if texts.count != items.count {
                reading = .unfollowed("a list item that is not a plain value")
            } else {
                var words: [String] = []
                var failed: Reading?
                for item in texts {
                    do {
                        let result = try Interpolation.resolve(item, variables)
                        unknown.formUnion(result.unknown)
                        words.append(result.value)
                    } catch {
                        failed = Self.reading(error)
                    }
                }
                reading = failed ?? .words(words)
            }
        default:
            written = .list([])
            reading = .unfollowed("a mapping where a command belongs")
        }
        self.written = written
        self.reading = reading
        self.stop = stop
        self.substituted = substituted
        unknownVariables = unknown
    }

    /// A string setting read: substituted, then split.
    struct StringReading {
        var reading: Reading
        var unknown: Set<String> = []
        var stop: CommandWords.Stop?
        var substituted: String?
    }

    static func readString(_ text: String, _ variables: Variables) -> StringReading {
        let result: Interpolation.Result
        do {
            result = try Interpolation.resolve(text, variables)
        } catch {
            return StringReading(reading: reading(error))
        }
        do {
            let split = try CommandWords.split(result.value)
            return StringReading(reading: .words(split.words), unknown: result.unknown, stop: split.stop,
                                 substituted: result.value)
        } catch {
            return StringReading(reading: reading(error), unknown: result.unknown, substituted: result.value)
        }
    }

    static func reading(_ failure: Interpolation.Failure) -> Reading {
        switch failure {
        case let .required(name): .refused("`\(name)` is required (`:?`) and the conversation does not set it")
        case .malformed: .unfollowed("a `$` this reader does not follow")
        }
    }

    static func reading(_ failure: CommandWords.Failure) -> Reading {
        switch failure {
        case let .refused(reason): .refused(reason)
        case let .unfollowed(reason): .unfollowed(reason)
        }
    }

    /// The same key and text, read as these words (for a misreading of the setting).
    init(replacing other: CommandSetting, words: [String]) {
        key = other.key
        written = other.written
        line = other.line
        reading = .words(words)
        unknownVariables = []
        stop = nil
        substituted = nil
    }

    /// The words, when compose's reading is known.
    public var words: [String]? {
        if case let .words(words) = reading, unknownVariables.isEmpty { return words }
        return nil
    }

    /// The text as written, for a string.
    public var text: String? {
        if case let .string(text) = written { return text }
        return nil
    }

    /// Whether the key is set to nothing (`[]` or `""`): the daemon then falls back to the image's value.
    var isEmpty: Bool {
        words?.isEmpty == true
    }

    /// The words as a shell would have read the string (a misreading): `sh -c "<text>"`.
    var shellReading: [String]? {
        guard let substituted, stop != nil, unknownVariables.isEmpty else { return nil }
        return ["/bin/sh", "-c", substituted]
    }

    /// The list read as if each item were split on spaces (a misreading).
    var splitItems: [String]? {
        guard case .list = written, let words, words.contains(where: { $0.contains(" ") }) else { return nil }
        return words.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
    }

    /// The written text or items, to search for variable names.
    var writtenTexts: [String] {
        switch written {
        case let .string(text): [text]
        case let .list(items): items
        }
    }
}
