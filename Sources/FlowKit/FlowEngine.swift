import Foundation

/// The one-stop entry point for embedding FlowKit in an app.
///
/// ```swift
/// let engine = FlowEngine(config: .appleOnDevice)            // on-device LLM
/// let flow   = try FlowParser.parse(url: myExportedFlowURL)  // your Langflow export
/// let answer = try await engine.reply("Hello", flow: flow)   // run it, get the text
/// ```
///
/// Customise it by passing your own `ComponentRegistry` (extra 1:1 components) and/or your own
/// `LLMProvider`s (e.g. a real OpenAI/Anthropic/MLX backend) — no need to fork the package.
public struct FlowEngine: Sendable {
    public let registry: ComponentRegistry
    public let services: Services

    /// Full control: supply a registry and pre-built services.
    public init(registry: ComponentRegistry = .standard(), services: Services) {
        self.registry = registry
        self.services = services
    }

    /// Convenience: build services from an `LLMConfig`, optionally overriding/adding providers by name.
    /// - Parameters:
    ///   - config: which backend each model node resolves to (see `LLMConfig.appleOnDevice` / `.echoOnly`).
    ///   - registry: 1:1 component implementations (defaults to the built-ins; add your own).
    ///   - providers: custom `LLMProvider`s keyed by provider name; these override the built-in factory.
    public init(config: LLMConfig,
                registry: ComponentRegistry = .standard(),
                providers: [String: any LLMProvider] = [:]) {
        self.registry = registry
        self.services = Services(llm: .from(config: config, extra: providers))
    }

    /// Run a flow. If `input` is given, it is injected into the flow's entry node (`ChatInput`/`TextInput`).
    @discardableResult
    public func run(_ flow: Flow,
                    input: String? = nil,
                    overrides: [String: [String: FlowValue]] = [:]) async throws -> ExecutionResult {
        var merged = overrides
        if let input, let entry = flow.inputNodes.first {
            merged[entry.id, default: [:]]["input_value"] = .text(input)
        }
        let executor = Executor(registry: registry, services: services)
        return try await executor.run(flow, overrides: merged)
    }

    /// Simplest path: run a flow with one user input and return the terminal message text.
    public func reply(_ input: String, flow: Flow) async throws -> String {
        let result = try await run(flow, input: input)
        return result.terminalMessages.last?.message.text ?? ""
    }
}
