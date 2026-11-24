@testable import ComposeCommandClaimKit
import Testing

/// Every row was probed with `docker compose config` (Docker Compose 2.32.4).
@Suite("How compose splits a command string")
struct CommandWordsTests {
    struct Row: Sendable, CustomStringConvertible {
        let text: String
        let words: [String]
        let mark: String?
        var description: String { text }
    }

    static let rows: [Row] = [
        Row(text: "npm run dev", words: ["npm", "run", "dev"], mark: nil),
        Row(text: "  echo   a\tb  ", words: ["echo", "a", "b"], mark: nil),
        Row(text: "echo a\necho b", words: ["echo", "a", "echo", "b"], mark: nil),
        Row(text: "cd /app && npm start", words: ["cd", "/app"], mark: "&&"),
        Row(text: "echo a; echo b", words: ["echo", "a"], mark: ";"),
        Row(text: "echo a | wc -l", words: ["echo", "a"], mark: "|"),
        Row(text: "echo a > f.txt", words: ["echo", "a"], mark: ">"),
        Row(text: "echo <in", words: ["echo"], mark: "<"),
        Row(text: "echo a||b", words: ["echo", "a"], mark: "||"),
        Row(text: "npm start &", words: ["npm", "start"], mark: "&"),
        Row(text: "echo a 2>&1", words: ["echo", "a"], mark: "2>&1"),
        Row(text: "echo x2>f", words: ["echo", "x2"], mark: ">"),
        Row(text: "echo 2x>f", words: ["echo"], mark: "2x>"),
        Row(text: "echo \"a\"2>f", words: ["echo", "a2"], mark: ">"),
        Row(text: "echo \"\"&&x", words: ["echo", ""], mark: "&&"),
        Row(text: "echo a && echo \"b", words: ["echo", "a"], mark: "&&"),
        Row(text: "echo a # note", words: ["echo", "a", "#", "note"], mark: nil),
        Row(text: "echo $(date) `id`", words: ["echo", "$(date)", "`id`"], mark: nil),
        Row(text: "echo $(a b) c", words: ["echo", "$(a b)", "c"], mark: nil),
        Row(text: "echo $(echo 'x; y')", words: ["echo", "$(echo 'x; y')"], mark: nil),
        Row(text: "echo `a;b` c", words: ["echo", "`a;b`", "c"], mark: nil),
        Row(text: "echo `'a b'` c", words: ["echo", "`a b`", "c"], mark: nil),
        Row(text: "echo \"`a b`\" \"$(a)\" \"(a)\"", words: ["echo", "`a b`", "$(a)", "(a)"], mark: nil),
        Row(text: "echo 'a && b' x", words: ["echo", "a && b", "x"], mark: nil),
        Row(text: "echo \"a\\\"b\" 'c\\nd' \"e\\nf\" \"\" x", words: ["echo", "a\"b", "c\\nd", "enf", "", "x"], mark: nil),
        Row(text: "echo \"a\" b\"c d\"e", words: ["echo", "a", "bc de"], mark: nil),
        Row(text: "echo a\\ \\ b a\\;b a\\|b \\(a\\)", words: ["echo", "a  b", "a;b", "a|b", "(a)"], mark: nil),
        Row(text: "echo ~ *.txt {b} [c] !d", words: ["echo", "~", "*.txt", "{b}", "[c]", "!d"], mark: nil),
        Row(text: "echo 'it''s'", words: ["echo", "its"], mark: nil),
        Row(text: "echo a\\tb", words: ["echo", "atb"], mark: nil)
    ]

    @Test(arguments: rows)
    func splits(_ row: Row) throws {
        let split = try CommandWords.split(row.text)
        #expect(split.words == row.words)
        #expect(split.stop?.mark == row.mark)
    }

    @Test func dropsTheRest() throws {
        #expect(try CommandWords.split("cd /app && npm start").stop?.dropped == "&& npm start")
        #expect(try CommandWords.split("echo 12>f").stop?.dropped == "12>f")
    }

    @Test(arguments: ["echo (a)", "echo a)", "echo $((1+2))", "echo $(a", "echo a\\", "echo \"open", "echo 'open",
                      "echo $(a)(b)"])
    func refused(_ text: String) {
        #expect(throws: CommandWords.Failure.refused(CommandWords.invalid)) { try CommandWords.split(text) }
    }

    @Test(arguments: ["echo `a", "echo `a\\b`", "echo `(a)`"])
    func unfollowed(_ text: String) {
        #expect(throws: CommandWords.Failure.self) { try CommandWords.split(text) }
        #expect((try? CommandWords.split(text)) == nil)
    }
}
