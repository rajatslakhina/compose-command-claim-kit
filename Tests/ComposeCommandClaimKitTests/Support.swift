@testable import ComposeCommandClaimKit
import Testing

let fence = "```"

func yaml(_ text: String) -> String {
    "\(fence)yaml\n\(text)\n\(fence)\n"
}

func dockerfile(_ text: String) -> String {
    "\(fence)dockerfile\n\(text)\n\(fence)\n"
}

func check(_ answer: String, context: String = "") -> CommandReport {
    CommandClaimChecker().check(answer, context: context)
}

func project(_ text: String, variables: Variables = Variables()) -> ComposeProject? {
    if case let .project(project) = ComposeProject.read(text, variables: variables) { return project }
    return nil
}

func service(_ text: String, _ name: String = "web", variables: Variables = Variables()) -> ComposeService? {
    project(text, variables: variables)?.service(name)
}

/// The findings of an answer that are not file lines.
func sentenceFindings(_ report: CommandReport) -> [CommandFinding] {
    report.findings.filter {
        if case .fileLine = $0.claim.kind { return false }
        return true
    }
}
