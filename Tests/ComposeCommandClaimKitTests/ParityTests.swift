@testable import ComposeCommandClaimKit
import DockerfileClaimKit
import EntrypointClaimKit
import Testing

@Suite("Parity with Docker Compose")
struct ParityTests {
    @Test(arguments: parityCases.indices)
    func sameProcess(_ index: Int) throws {
        let row = parityCases[index]
        var variables = Variables(shell: row.shell, dotEnv: EnvFile.parse(row.dotEnv.components(separatedBy: "\n")))
        variables.unset = Set(Interpolation.names(in: row.compose)).filter { !variables.knows($0) }
        let web = try #require(service(row.compose, variables: variables))
        guard let expected = row.expected else {
            #expect(web.settings.contains { if case .refused = $0.reading { true } else { false } }, "\(row.compose)")
            return
        }
        let run = try row.run.map { try #require(RunCommand.parse($0)) }
        let process = try #require(ContainerProcess.of(web, image: ImageCommands(Dockerfile(row.dockerfile)), run: run))
        #expect(process.words == expected, "\(row.compose) \(row.run ?? "")")
    }

    @Test func coversTheShapes() {
        #expect(parityCases.count >= 250)
        #expect(parityCases.contains { $0.expected == nil })
        #expect(parityCases.contains { $0.expected == [] })
        #expect(parityCases.filter { $0.run != nil }.count >= 50)
    }
}
