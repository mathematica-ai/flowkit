import Foundation

// 1:1 native implementations of a starter set of n8n node types, keyed by the
// n8n `type` string. n8n passes "items" (JSON objects) along the single `"main"`
// conduit; each component reads the upstream item from `inputs["main"]` and its
// own configuration from the other `inputs` (the node's `parameters`).
//
// Scope: the on-device-meaningful subset — a trigger, item logic (Set/NoOp), and
// an LLM node. Integration nodes (HTTP/Slack/DB) are inherently networked and out
// of scope for an offline runner.

/// `manualTrigger` / `start` — kicks off the workflow with a seed item. Accepts a
/// `seed` parameter (a dict) or a runtime-injected `input_value`.
public struct N8nTriggerComponent: Component {
    public init() {}
    public func run(_ ctx: ComponentContext) async throws -> [String: FlowValue] {
        if let seed = ctx.inputs["seed"] { return ["main": seed] }
        if let input = ctx.inputs["input_value"]?.asText { return ["main": .dict(["input": .text(input)])] }
        return ["main": .dict([:])]
    }
}

/// `set` / `editFields` — evaluates each assignment's value expression against the
/// input item and merges the results onto it. Reads the n8n v3 shape
/// `assignments.assignments: [{ name, value, type }]`.
public struct N8nSetComponent: Component {
    public init() {}
    public func run(_ ctx: ComponentContext) async throws -> [String: FlowValue] {
        let inputItem = ctx.inputs["main"] ?? .dict([:])
        var item = inputItem.asDict ?? [:]
        if let container = ctx.inputs["assignments"]?.asDict,
           case let .list(entries)? = container["assignments"] {
            for entry in entries {
                guard let fields = entry.asDict, let name = fields["name"]?.asText else { continue }
                let raw = fields["value"]?.asText ?? ""
                item[name] = N8nExpression.evaluate(raw, item: inputItem)
            }
        }
        return ["main": .dict(item)]
    }
}

/// `noOp` — passthrough.
public struct N8nNoOpComponent: Component {
    public init() {}
    public func run(_ ctx: ComponentContext) async throws -> [String: FlowValue] {
        ["main": ctx.inputs["main"] ?? .dict([:])]
    }
}

/// The n8n LLM/agent node — routes to the config-bound `LLMProvider` (Apple
/// Foundation Models on-device, by default). Reads a `text`/`prompt` parameter
/// (expression-evaluated against the item), runs it, and adds `text` to the item.
public struct N8nLLMComponent: Component {
    public init() {}
    public func run(_ ctx: ComponentContext) async throws -> [String: FlowValue] {
        let item = ctx.inputs["main"] ?? .dict([:])
        let rawPrompt = ctx.inputs["text"]?.asText ?? ctx.inputs["prompt"]?.asText ?? item.asText
        let prompt = N8nExpression.evaluate(rawPrompt, item: item).asText
        guard let provider = ctx.services.llm.provider(for: ctx.node) else {
            throw FlowError.noLLMProvider(node: ctx.node.id)
        }
        let answer = try await provider.generate(system: nil, user: prompt)
        var out = item.asDict ?? [:]
        out["text"] = .text(answer)
        return ["main": .dict(out)]
    }
}

public extension ComponentRegistry {
    /// Starter registry of n8n node types. Extend as you add more.
    static func n8nStandard() -> ComponentRegistry {
        var registry = ComponentRegistry()
        registry.register(["n8n-nodes-base.manualTrigger", "n8n-nodes-base.start"], N8nTriggerComponent())
        registry.register(["n8n-nodes-base.set", "n8n-nodes-base.editFields"], N8nSetComponent())
        registry.register("n8n-nodes-base.noOp", N8nNoOpComponent())
        registry.register(
            ["@n8n/n8n-nodes-langchain.openAi", "@n8n/n8n-nodes-langchain.agent", "n8n-nodes-base.openAi"],
            N8nLLMComponent()
        )
        return registry
    }
}
