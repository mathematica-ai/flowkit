import Foundation

public struct TerminalOutput: Sendable {
    public let nodeId: String
    public let message: Message
}

public struct ExecutionResult: Sendable {
    /// nodeId -> (outputName -> value)
    public let nodeOutputs: [String: [String: FlowValue]]
    /// Messages produced by terminal ChatOutput nodes, in execution order.
    public let terminalMessages: [TerminalOutput]
}

/// Walks the flow DAG in topological order, resolving each node against the registry and passing
/// values along edges. Execution is sequential for now (parallelising independent branches is a
/// straightforward future enhancement).
public struct Executor {
    public let registry: ComponentRegistry
    public let services: Services

    public init(registry: ComponentRegistry, services: Services) {
        self.registry = registry
        self.services = services
    }

    /// - Parameter overrides: runtime input values keyed by nodeId → fieldName. Applied after
    ///   template defaults but before edge-delivered values (used to inject user input into a flow).
    public func run(_ flow: Flow,
                    overrides: [String: [String: FlowValue]] = [:]) async throws -> ExecutionResult {
        let order = try topologicalOrder(flow)
        var outputs: [String: [String: FlowValue]] = [:]
        var terminals: [TerminalOutput] = []

        for nodeId in order {
            guard let node = flow.node(id: nodeId) else { continue }
            guard let component = registry.component(for: node.type) else {
                throw FlowError.unknownComponent(type: node.type, node: node.id,
                                                 known: registry.registeredTypes)
            }

            // 1) static template values
            var inputs: [String: FlowValue] = [:]
            for (field, tf) in node.template {
                if let v = tf.value { inputs[field] = v }
            }
            // 1.5) runtime overrides (e.g. user-typed input)
            if let nodeOverrides = overrides[nodeId] {
                for (field, value) in nodeOverrides { inputs[field] = value }
            }
            // 2) override with values delivered along incoming edges
            for edge in flow.edges where edge.target == nodeId {
                guard let upstream = outputs[edge.source] else { continue }
                // Resolve by output name; if the named output is absent but the node produced
                // exactly one output, use it (resilience to output-name drift).
                let value = upstream[edge.sourceOutput] ?? (upstream.count == 1 ? upstream.values.first : nil)
                if let value { inputs[edge.targetField] = value }
            }

            let ctx = ComponentContext(node: node, inputs: inputs, services: services)
            let produced = try await component.run(ctx)
            outputs[nodeId] = produced

            if node.type == "ChatOutput" {
                let msg = (produced["message"] ?? produced.values.first)?.asMessage ?? Message(text: "")
                terminals.append(TerminalOutput(nodeId: nodeId, message: msg))
            }
        }

        return ExecutionResult(nodeOutputs: outputs, terminalMessages: terminals)
    }

    // Kahn's algorithm; preserves node declaration order for deterministic runs.
    func topologicalOrder(_ flow: Flow) throws -> [String] {
        var indegree: [String: Int] = [:]
        var adjacency: [String: [String]] = [:]
        for n in flow.nodes { indegree[n.id] = 0 }
        for e in flow.edges {
            adjacency[e.source, default: []].append(e.target)
            indegree[e.target, default: 0] += 1
            if indegree[e.source] == nil { indegree[e.source] = 0 }
        }

        var queue = flow.nodes.map(\.id).filter { (indegree[$0] ?? 0) == 0 }
        var order: [String] = []
        var head = 0
        while head < queue.count {
            let id = queue[head]; head += 1
            order.append(id)
            for next in adjacency[id] ?? [] {
                indegree[next, default: 0] -= 1
                if indegree[next] == 0 { queue.append(next) }
            }
        }

        guard order.count == flow.nodes.count else { throw FlowError.cycleDetected }
        return order
    }
}
