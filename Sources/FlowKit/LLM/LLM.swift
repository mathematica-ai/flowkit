import Foundation

// MARK: - Provider protocol
//
// Every backend (Apple Foundation Models / "Siri AI", OpenAI, Anthropic, a local MLX model…)
// conforms to this. Components only ever see the protocol — the concrete backend is chosen by
// configuration, not baked into the flow.

public protocol LLMProvider: Sendable {
    func generate(system: String?, user: String) async throws -> String
}

// MARK: - Config file model
//
// Maps a flow's abstract LLM slot to a concrete backend. `default` applies to every model node;
// `overrides` can pin a specific node id to a named provider.

public struct LLMConfig: Codable, Sendable {
    public var defaultProvider: String
    public var overrides: [String: String]
    public var providers: [String: ProviderSpec]

    public struct ProviderSpec: Codable, Sendable {
        public var backend: String          // "echo" | "foundation_models" | "openai" | "anthropic"
        public var model: String?
        public var keyRef: String?          // e.g. "keychain:openai" — resolved by the host app
        public init(backend: String, model: String? = nil, keyRef: String? = nil) {
            self.backend = backend; self.model = model; self.keyRef = keyRef
        }
    }

    enum CodingKeys: String, CodingKey {
        case defaultProvider = "default"
        case overrides, providers
    }

    public init(defaultProvider: String, overrides: [String: String], providers: [String: ProviderSpec]) {
        self.defaultProvider = defaultProvider
        self.overrides = overrides
        self.providers = providers
    }

    /// Offline, zero-dependency default (deterministic echo provider).
    public static let echoOnly = LLMConfig(
        defaultProvider: "echo",
        overrides: [:],
        providers: ["echo": .init(backend: "echo")]
    )

    /// 100% on-device via Apple Foundation Models, with the echo provider as a fallback name.
    public static let appleOnDevice = LLMConfig(
        defaultProvider: "siri",
        overrides: [:],
        providers: [
            "siri": .init(backend: "foundation_models"),
            "echo": .init(backend: "echo"),
        ]
    )
}

// MARK: - Resolver (config -> live providers, picked per node)

public struct LLMResolver: Sendable {
    public let config: LLMConfig
    public let providers: [String: any LLMProvider]

    public init(config: LLMConfig, providers: [String: any LLMProvider]) {
        self.config = config
        self.providers = providers
    }

    public func provider(for node: FlowNode) -> (any LLMProvider)? {
        let name = config.overrides[node.id] ?? config.defaultProvider
        return providers[name]
    }

    /// Build a resolver by instantiating each provider spec from the config.
    /// - Parameter extra: custom providers keyed by name that override the built-in factory
    ///   (how a host app injects a real OpenAI/Anthropic/MLX backend).
    public static func from(config: LLMConfig,
                            extra: [String: any LLMProvider] = [:]) -> LLMResolver {
        var live: [String: any LLMProvider] = [:]
        for (name, spec) in config.providers {
            live[name] = LLMBackendFactory.make(name: name, spec: spec)
        }
        for (name, provider) in extra { live[name] = provider }
        return LLMResolver(config: config, providers: live)
    }
}

// MARK: - Backend factory

public enum LLMBackendFactory {
    public static func make(name: String, spec: LLMConfig.ProviderSpec) -> any LLMProvider {
        switch spec.backend {
        case "echo":
            return EchoLLMProvider()
        case "foundation_models":
            if #available(macOS 26.0, iOS 26.0, *) {
                return FoundationModelsProvider()
            } else {
                return UnavailableLLMProvider(reason: "Foundation Models requires macOS/iOS 26+")
            }
        case "openai":
            return UnavailableLLMProvider(
                reason: "OpenAI backend is a scaffold stub — add the MacPaw/OpenAI package and resolve key \(spec.keyRef ?? "(none)")")
        case "anthropic":
            return UnavailableLLMProvider(
                reason: "Anthropic backend is a scaffold stub — add SwiftAnthropic and resolve key \(spec.keyRef ?? "(none)")")
        default:
            return UnavailableLLMProvider(reason: "Unknown backend \"\(spec.backend)\" for provider \"\(name)\"")
        }
    }
}

// MARK: - Built-in providers

/// Deterministic, dependency-free stand-in so flows run end-to-end with zero setup (and tests stay
/// deterministic). Swap it out via llm-config.json.
public struct EchoLLMProvider: LLMProvider {
    public init() {}
    public func generate(system: String?, user: String) async throws -> String {
        let prefix = system.map { "[system: \($0)] " } ?? ""
        return "\(prefix)You asked: \"\(user)\" — (echo provider; configure a real backend in llm-config.json)"
    }
}

/// Placeholder for backends that aren't wired in this scaffold; fails with a clear message.
public struct UnavailableLLMProvider: LLMProvider {
    public let reason: String
    public init(reason: String) { self.reason = reason }
    public func generate(system: String?, user: String) async throws -> String {
        throw LLMError.notImplemented(reason)
    }
}
