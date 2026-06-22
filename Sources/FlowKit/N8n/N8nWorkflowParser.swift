import Foundation

/// Parses an **n8n** workflow export into the shared `Flow` model — the n8n
/// counterpart to `FlowParser` (Langflow). Same engine underneath; only the
/// front-end format differs.
///
/// n8n shape: `nodes[]` (each `{ name, type, parameters }`) plus `connections`,
/// a map keyed by source-node **name** → `main` → output-index → `[{ node, index }]`.
/// We key nodes on their `name` (which is how connections reference them), map
/// `parameters` into the node template, and model the item conduit as a single
/// `"main"` output/input.
public enum N8nWorkflowParser {

    public static func parse(data: Data) throws -> Flow {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FlowError.malformed("n8n: root is not an object")
        }
        let rawNodes = root["nodes"] as? [[String: Any]] ?? []
        let connections = root["connections"] as? [String: Any] ?? [:]

        let nodes = rawNodes.compactMap(parseNode)
        let edges = parseConnections(connections)
        return Flow(nodes: nodes, edges: edges)
    }

    public static func parse(url: URL) throws -> Flow {
        try parse(data: Data(contentsOf: url))
    }

    static func parseNode(_ n: [String: Any]) -> FlowNode? {
        // n8n connections reference nodes by `name`; use it as the node id.
        guard let name = (n["name"] as? String) ?? (n["id"] as? String),
              let type = n["type"] as? String else { return nil }

        var template: [String: TemplateField] = [:]
        if let parameters = n["parameters"] as? [String: Any] {
            for (key, value) in parameters {
                template[key] = TemplateField(value: FlowValue.fromJSON(value), valueType: nil, inputTypes: [])
            }
        }
        return FlowNode(id: name, type: type, displayName: name,
                        template: template, outputs: [NodeOutput(name: "main", types: [])])
    }

    static func parseConnections(_ connections: [String: Any]) -> [FlowEdge] {
        var edges: [FlowEdge] = []
        for (sourceName, conn) in connections {
            guard let connDict = conn as? [String: Any],
                  let main = connDict["main"] as? [Any] else { continue }
            for (outputIndex, branchAny) in main.enumerated() {
                guard let branch = branchAny as? [Any] else { continue }   // null = unconnected output
                let sourceOutput = outputIndex == 0 ? "main" : "main_\(outputIndex)"
                for targetAny in branch {
                    guard let target = targetAny as? [String: Any],
                          let targetNode = target["node"] as? String else { continue }
                    edges.append(FlowEdge(source: sourceName, target: targetNode,
                                          sourceOutput: sourceOutput, targetField: "main"))
                }
            }
        }
        return edges
    }
}

public extension SampleFlows {
    /// Parse a bundled n8n workflow sample by name.
    static func n8nWorkflow(_ name: String) throws -> Flow {
        try N8nWorkflowParser.parse(data: data(name))
    }
}
