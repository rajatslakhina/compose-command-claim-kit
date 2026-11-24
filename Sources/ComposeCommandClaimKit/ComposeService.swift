/// One service of a compose file, as far as starting its container goes.
public struct ComposeService: Sendable, Hashable {
    public let name: String
    public let image: String?
    /// The service has `build:`: its image comes from a Dockerfile.
    public let builds: Bool
    /// `command:`, when set (and not `null`).
    public internal(set) var command: CommandSetting?
    /// `entrypoint:`, when set (and not `null`).
    public internal(set) var entrypoint: CommandSetting?
    /// The service's `environment:`: set in the container, never substituted into the file.
    public let environment: [String: String]
    let node: ComposeNode

    init(name: String, node: ComposeNode, variables: Variables) {
        self.name = name
        self.node = node
        image = node["image"]?.text
        builds = node["build"] != nil
        command = Self.setting("command", in: node, variables: variables)
        entrypoint = Self.setting("entrypoint", in: node, variables: variables)
        environment = Self.environment(node["environment"])
    }

    static func setting(_ key: String, in node: ComposeNode, variables: Variables) -> CommandSetting? {
        guard let entry = node.entry(key), entry.value != .null else { return nil }
        return CommandSetting(key: key, node: entry.value, line: entry.line, variables: variables)
    }

    /// `environment:` as a mapping (`KEY: value`) or a list (`- KEY=value`); a bare `- KEY` comes from the shell.
    static func environment(_ node: ComposeNode?) -> [String: String] {
        var values: [String: String] = [:]
        for entry in node?.entries ?? [] {
            values[entry.key] = entry.value.text ?? ""
        }
        for item in node?.items?.compactMap(\.text) ?? [] {
            guard let equals = item.firstIndex(of: "=") else { continue }
            values[String(item[..<equals])] = String(item[item.index(after: equals)...])
        }
        return values
    }

    /// The settings in the order compose sends them: `entrypoint`, then `command`.
    var settings: [CommandSetting] {
        [entrypoint, command].compactMap { $0 }
    }

    /// The service read again with other variables (for a misreading of where they come from).
    func reread(_ variables: Variables) -> ComposeService {
        ComposeService(name: name, node: node, variables: variables)
    }

    /// Why the words of this service's settings are not known.
    var unknownReason: String {
        for setting in settings {
            switch setting.reading {
            case let .refused(reason):
                return "`docker compose` refuses this file: `\(name)`'s `\(setting.key):` has \(reason)"
            case let .unfollowed(reason):
                return "`\(name)`'s `\(setting.key):` uses \(reason), which this reader does not follow"
            case .words:
                if let name = setting.unknownVariables.min() {
                    return "`\(self.name)`'s `\(setting.key):` uses `$\(name)`, which compose takes from your shell, "
                        + "and the conversation does not show its value"
                }
            }
        }
        return "`\(name)`'s command is not known"
    }

    /// The names written with one `$` in this service's settings.
    var substitutedNames: [String] {
        settings.flatMap(\.writtenTexts).flatMap(Interpolation.names(in:))
    }

    /// The names written as `$$NAME` in this service's settings.
    var escapedNames: [String] {
        settings.flatMap(\.writtenTexts).flatMap(Interpolation.escapedNames(in:))
    }
}

/// The services of one compose file. A Kubernetes manifest (`apiVersion:`, `kind:`) is not one: its `command:`
/// replaces the image's ENTRYPOINT, the opposite of compose.
public struct ComposeProject: Sendable, Hashable {
    public let services: [ComposeService]

    public init(services: [ComposeService]) {
        self.services = services
    }

    public enum Reading: Sendable, Hashable {
        case project(ComposeProject)
        /// A compose file this reader does not follow, and why.
        case unfollowed(String)
        /// Not a compose file.
        case notCompose
    }

    public static func read(_ text: String, variables: Variables = Variables()) -> Reading {
        let root: ComposeNode
        do {
            root = try ComposeYAML.parse(text)
        } catch {
            return looksLikeCompose(text) ? .unfollowed(error.reason) : .notCompose
        }
        guard root["apiVersion"] == nil, root["kind"] == nil, let services = root["services"]?.entries else {
            return .notCompose
        }
        return .project(ComposeProject(services: services.map {
            ComposeService(name: $0.key, node: $0.value, variables: variables)
        }))
    }

    /// Text with a top-level `services:` line and no Kubernetes keys.
    static func looksLikeCompose(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        let topLevel = lines.filter { $0.first.map { !$0.isWhitespace } == true }
        return topLevel.contains { $0.hasPrefix("services:") }
            && !topLevel.contains { $0.hasPrefix("apiVersion:") || $0.hasPrefix("kind:") }
    }

    public func service(_ name: String) -> ComposeService? {
        services.first { $0.name == name }
    }
}
