import Foundation

/// Parses a Langflow flow export (the ReactFlow JSON document) into a typed `Flow`.
///
/// Key design point: we resolve nodes by **`data.type`** (the component class name) and read the
/// declarative **`data.node.template`** of typed inputs. We deliberately ignore `template.code`
/// (the embedded Python source) — behaviour comes from the 1:1 native Swift component instead.
public enum FlowParser {

    public static func parse(data: Data) throws -> Flow {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FlowError.malformed("root is not an object")
        }
        guard let dataObj = root["data"] as? [String: Any] else {
            throw FlowError.malformed("missing top-level \"data\" object")
        }
        let rawNodes = dataObj["nodes"] as? [[String: Any]] ?? []
        let rawEdges = dataObj["edges"] as? [[String: Any]] ?? []
        let nodes = rawNodes.compactMap(parseNode)
        let edges = rawEdges.compactMap(parseEdge)
        return Flow(nodes: nodes, edges: edges)
    }

    public static func parse(url: URL) throws -> Flow {
        try parse(data: Data(contentsOf: url))
    }

    // MARK: - Nodes

    static func parseNode(_ n: [String: Any]) -> FlowNode? {
        guard let id = n["id"] as? String,
              let d = n["data"] as? [String: Any],
              let type = d["type"] as? String else { return nil }   // skips non-component nodes (e.g. notes)

        let node = d["node"] as? [String: Any] ?? [:]
        let displayName = node["display_name"] as? String

        var template: [String: TemplateField] = [:]
        if let tmpl = node["template"] as? [String: Any] {
            for (fieldName, raw) in tmpl {
                if fieldName == "_type" || fieldName == "code" { continue }   // metadata / Python source
                guard let field = raw as? [String: Any] else { continue }
                let value = field["value"].map(FlowValue.fromJSON)
                let vtype = field["type"] as? String
                let itypes = field["input_types"] as? [String] ?? []
                template[fieldName] = TemplateField(value: value, valueType: vtype, inputTypes: itypes)
            }
        }

        var outputs: [NodeOutput] = []
        if let outs = node["outputs"] as? [[String: Any]] {
            for o in outs where (o["name"] as? String) != nil {
                outputs.append(NodeOutput(name: o["name"] as! String, types: o["types"] as? [String] ?? []))
            }
        }

        return FlowNode(id: id, type: type, displayName: displayName, template: template, outputs: outputs)
    }

    // MARK: - Edges

    static func parseEdge(_ e: [String: Any]) -> FlowEdge? {
        guard let source = e["source"] as? String,
              let target = e["target"] as? String else { return nil }

        // Prefer the pre-decoded objects under `edge.data`; fall back to the œ-escaped string handles.
        let dataObj = e["data"] as? [String: Any]
        let src = handleObject(preferred: dataObj?["sourceHandle"], rawString: e["sourceHandle"] as? String)
        let tgt = handleObject(preferred: dataObj?["targetHandle"], rawString: e["targetHandle"] as? String)

        let sourceOutput = (src?["name"] as? String) ?? ""
        let targetField  = (tgt?["fieldName"] as? String) ?? ""
        return FlowEdge(source: source, target: target, sourceOutput: sourceOutput, targetField: targetField)
    }

    static func handleObject(preferred: Any?, rawString: String?) -> [String: Any]? {
        if let obj = preferred as? [String: Any] { return obj }
        if let s = rawString { return decodeEscapedHandle(s) }
        return nil
    }

    /// Langflow encodes handle JSON inside a string, escaping every `"` as the ligature `œ` (U+0153)
    /// so the JSON survives being embedded in JSON. Reverse it and parse.
    public static func decodeEscapedHandle(_ raw: String) -> [String: Any]? {
        let json = raw.replacingOccurrences(of: "œ", with: "\"")
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }
}
