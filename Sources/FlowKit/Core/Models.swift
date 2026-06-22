import Foundation

// MARK: - Message
// The primary value type that flows along most Langflow edges (port type "Message").

public struct Message: Sendable, Equatable, Codable {
    public var text: String
    public var sender: String?       // "User" / "AI" / "Machine"
    public var senderName: String?
    public init(text: String, sender: String? = nil, senderName: String? = nil) {
        self.text = text
        self.sender = sender
        self.senderName = senderName
    }
}

// MARK: - FlowValue
// A runtime value passed between components. Mirrors the JSON value space plus Message.

public enum FlowValue: Sendable, Equatable {
    case message(Message)
    case text(String)
    case number(Double)
    case bool(Bool)
    case list([FlowValue])
    case dict([String: FlowValue])
    case null

    /// Best-effort textual rendering, used when a component expects text.
    public var asText: String {
        switch self {
        case .message(let m): return m.text
        case .text(let s):    return s
        case .number(let n):  return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b):    return String(b)
        case .null:           return ""
        case .list, .dict:    return ""
        }
    }

    /// Coerce to a Message (wrapping text if needed).
    public var asMessage: Message {
        if case .message(let m) = self { return m }
        return Message(text: asText)
    }

    /// The underlying dictionary, if this is a `.dict` (an n8n item is a dict).
    public var asDict: [String: FlowValue]? {
        if case .dict(let d) = self { return d }
        return nil
    }

    /// Convert to a Foundation value (String / Double / Bool / Array / Dictionary /
    /// NSNull) — used to bind `$json` into a JavaScriptCore context for n8n expressions.
    public func toFoundation() -> Any {
        switch self {
        case .message(let m): return m.text
        case .text(let s):    return s
        case .number(let n):  return n
        case .bool(let b):    return b
        case .null:           return NSNull()
        case .list(let a):    return a.map { $0.toFoundation() }
        case .dict(let d):    return d.mapValues { $0.toFoundation() }
        }
    }

    /// Convert a JSONSerialization value (`Any`) into a FlowValue.
    static func fromJSON(_ any: Any) -> FlowValue {
        switch any {
        case is NSNull:
            return .null
        case let s as String:
            return .text(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        case let arr as [Any]:
            return .list(arr.map(FlowValue.fromJSON))
        case let dict as [String: Any]:
            var out: [String: FlowValue] = [:]
            for (k, v) in dict { out[k] = FlowValue.fromJSON(v) }
            return .dict(out)
        default:
            return .null
        }
    }
}

// MARK: - Parsed flow graph

public struct Flow: Sendable {
    public var nodes: [FlowNode]
    public var edges: [FlowEdge]
    public init(nodes: [FlowNode], edges: [FlowEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
    public func node(id: String) -> FlowNode? { nodes.first { $0.id == id } }

    /// Entry-point nodes a user can type into (no incoming edges expected).
    public var inputNodes: [FlowNode] {
        nodes.filter { $0.type == "ChatInput" || $0.type == "TextInput" }
    }
}

/// A node = one component instance. `type` is the registry key (Langflow `data.type`).
public struct FlowNode: Sendable {
    public let id: String                       // e.g. "TextInput-J1CQK"
    public let type: String                     // e.g. "TextInput"  ← matched 1:1 against the registry
    public let displayName: String?
    public let template: [String: TemplateField]   // input field name -> field
    public let outputs: [NodeOutput]
    public init(id: String, type: String, displayName: String?,
                template: [String: TemplateField], outputs: [NodeOutput]) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.template = template
        self.outputs = outputs
    }
}

public struct TemplateField: Sendable {
    public let value: FlowValue?
    public let valueType: String?
    public let inputTypes: [String]
    public init(value: FlowValue?, valueType: String?, inputTypes: [String]) {
        self.value = value
        self.valueType = valueType
        self.inputTypes = inputTypes
    }
}

public struct NodeOutput: Sendable {
    public let name: String
    public let types: [String]
    public init(name: String, types: [String]) {
        self.name = name
        self.types = types
    }
}

/// An edge wires one node's named output into another node's named input field.
public struct FlowEdge: Sendable {
    public let source: String        // source node id
    public let target: String        // target node id
    public let sourceOutput: String  // output name (handle "name")
    public let targetField: String   // input field name (handle "fieldName")
    public init(source: String, target: String, sourceOutput: String, targetField: String) {
        self.source = source
        self.target = target
        self.sourceOutput = sourceOutput
        self.targetField = targetField
    }
}
