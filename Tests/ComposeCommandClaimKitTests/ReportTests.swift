@testable import ComposeCommandClaimKit
import Testing

@Suite("Reports and the ledger")
struct ReportTests {
    let claim = CommandClaim(kind: .runs(service: "web", stated: "x", run: nil), sentence: "`web` runs `x`.")

    @Test func verdicts() {
        #expect(CommandReport(findings: []).verdict == .noClaims)
        #expect(CommandReport(findings: []).summary == "no claims about compose commands")
        #expect(CommandReport(findings: []).note == nil && CommandReport(findings: []).feedback == nil)
        let holds = CommandFinding(claim: claim, outcome: .exact)
        let unchecked = CommandFinding(claim: claim, outcome: .unchecked("why"))
        let caution = CommandFinding(claim: claim, outcome: .caveat(.entrypointPrefix), actual: "Caveat.")
        var wrong = CommandFinding(claim: claim, outcome: .wrong(.listItemSplit), actual: "Wrong.")
        wrong.isRepeated = true
        #expect(CommandReport(findings: [holds]).verdict == .verified)
        #expect(CommandReport(findings: [holds, unchecked]).verdict == .unchecked)
        #expect(CommandReport(findings: [unchecked, caution]).verdict == .caution)
        let all = CommandReport(findings: [holds, unchecked, caution, wrong])
        #expect(all.verdict == .wrong)
        #expect(all.summary == "4 claims checked, 1 hold, 1 unchecked, 1 to check, 1 wrong, 1 repeated")
        #expect(CommandReport(findings: [holds]).summary == "1 claim checked, 1 hold")
        #expect(all.corrections == ["Caveat.", "Wrong."])
        #expect(all.note == "Compose command check: Caveat. Wrong. Some of this was stated again after a correction "
            + "was asked for.")
        #expect(CommandReport(findings: [caution]).note == "Compose command check: Caveat.")
        #expect(all.feedback?.contains("- Wrong.") == true)
        #expect(holds.explanation == "Holds." && unchecked.explanation == "Not checked: why.")
        #expect(holds.actual == nil && wrong.actual == "Wrong." && holds.slip == nil)
        #expect(CommandFinding.Severity.holds < .wrong)
    }

    @Test func ledger() async {
        let ledger = CommandLedger()
        let first = await ledger.review(yaml("services:\n  web:\n    image: node:20\n    command: npm run dev"))
        #expect(first.verdict == .noClaims)
        let second = await ledger.review("`web` runs `npm run dev`. Compose runs `command` through a shell.")
        #expect(second.verdict == .wrong && second.repeatedCount == 0)
        let third = await ledger.review("Again: compose runs `command` through a shell.")
        #expect(third.repeatedCount == 1)
        let statistics = await ledger.statistics
        #expect(statistics == CommandLedger.Statistics(reviews: 3, claims: 3, flagged: 2, repeated: 1))
        await ledger.forget()
        let fresh = await ledger.review("`web` runs `npm run dev`.")
        #expect(fresh.verdict == .noClaims)
        #expect(ledger.checker.reader.checksFileLines)
    }
}
