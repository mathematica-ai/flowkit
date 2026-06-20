import Foundation

// MARK: - Component model
//
// A Component is the 1:1 native Swift implementation of a Langflow component, keyed by its
// `data.type` name. It receives its already-resolved inputs (template defaults + values delivered
// along edges) and returns a dictionary of named outputs.

public struct ComponentContext: Sendable {
    public let node: FlowNode
    public let inputs: [String: FlowValue]   // input field name -> value
    public let services: Services
    public init(node: FlowNode, inputs: [String: FlowValue], services: Services) {
        self.node = node
        self.inputs = inputs
        self.services = services
    }
}

public protocol Component: Sendable {
    /// Returns outputs keyed by output name (matching `data.node.outputs[].name`).
    func run(_ ctx: ComponentContext) async throws -> [String: FlowValue]
}

// MARK: - Registry (component name -> implementation)

public struct ComponentRegistry: Sendable {
    private var byType: [String: any Component] = [:]
    public init() {}

    public mutating func register(_ type: String, _ component: any Component) {
        byType[type] = component
    }

    /// Register one implementation under several Langflow names (e.g. all provider model nodes
    /// collapse to a single abstract LanguageModel slot).
    public mutating func register(_ types: [String], _ component: any Component) {
        for t in types { byType[t] = component }
    }

    public func component(for type: String) -> (any Component)? { byType[type] }

    public var registeredTypes: [String] { byType.keys.sorted() }
}

// MARK: - Runtime services available to components

public struct Services: Sendable {
    public let llm: LLMResolver
    public init(llm: LLMResolver) { self.llm = llm }
}
