import Foundation

// 1:1 native Swift implementations of Langflow components, keyed by `data.type`.
// "Logic" components are deterministic native code; the LanguageModel slot is config-bound.

/// Langflow `TextInput` → emits its `input_value` as a Message on output "text".
public struct TextInputComponent: Component {
    public init() {}
    public func run(_ ctx: ComponentContext) async throws -> [String: FlowValue] {
        let text = ctx.inputs["input_value"]?.asText ?? ""
        return ["text": .message(Message(text: text))]
    }
}

/// Langflow `ChatInput` → emits a user Message on output "message".
public struct ChatInputComponent: Component {
    public init() {}
    public func run(_ ctx: ComponentContext) async throws -> [String: FlowValue] {
        let text = ctx.inputs["input_value"]?.asText ?? ""
        return ["message": .message(Message(text: text, sender: "User", senderName: "User"))]
    }
}

/// Langflow `Prompt` → fills `{variables}` in `template` from connected inputs; output "prompt".
public struct PromptComponent: Component {
    public init() {}
    public func run(_ ctx: ComponentContext) async throws -> [String: FlowValue] {
        var result = ctx.inputs["template"]?.asText ?? ""
        for (key, value) in ctx.inputs where key != "template" {
            result = result.replacingOccurrences(of: "{\(key)}", with: value.asText)
        }
        return ["prompt": .message(Message(text: result))]
    }
}

/// Langflow `ChatOutput` → terminal sink; passes its input through on output "message".
public struct ChatOutputComponent: Component {
    public init() {}
    public func run(_ ctx: ComponentContext) async throws -> [String: FlowValue] {
        let message = (ctx.inputs["input_value"] ?? ctx.inputs.values.first)?.asMessage ?? Message(text: "")
        return ["message": .message(message)]
    }
}

/// The abstract LLM slot. Every Langflow model component (LanguageModel / OpenAIModel /
/// AnthropicModel / …) maps here; the concrete backend is resolved from config per node.
/// Output "text_output".
public struct LanguageModelComponent: Component {
    public init() {}
    public func run(_ ctx: ComponentContext) async throws -> [String: FlowValue] {
        let user = (ctx.inputs["input_value"] ?? ctx.inputs["prompt"])?.asText ?? ""
        let system = ctx.inputs["system_message"]?.asText
        guard let provider = ctx.services.llm.provider(for: ctx.node) else {
            throw FlowError.noLLMProvider(node: ctx.node.id)
        }
        let answer = try await provider.generate(system: system, user: user)
        return ["text_output": .message(Message(text: answer, sender: "AI", senderName: "AI"))]
    }
}

// MARK: - Default registry

public extension ComponentRegistry {
    /// The components this scaffold ships. Extend this as you add 1:1 implementations.
    static func standard() -> ComponentRegistry {
        var registry = ComponentRegistry()
        registry.register("TextInput", TextInputComponent())
        registry.register("ChatInput", ChatInputComponent())
        registry.register("Prompt", PromptComponent())
        registry.register("ChatOutput", ChatOutputComponent())
        // Provider-specific model nodes collapse to one config-bound slot:
        registry.register(
            ["LanguageModel", "OpenAIModel", "AnthropicModel", "GoogleGenerativeAIModel"],
            LanguageModelComponent()
        )
        return registry
    }
}
