import Foundation

public enum FlowError: Error, CustomStringConvertible {
    case malformed(String)
    case unknownComponent(type: String, node: String, known: [String])
    case cycleDetected
    case noLLMProvider(node: String)

    public var description: String {
        switch self {
        case .malformed(let why):
            return "Malformed flow JSON: \(why)"
        case .unknownComponent(let type, let node, let known):
            return """
            Unknown component "\(type)" (node \(node)). No 1:1 Swift implementation is registered for it.
            Register one with ComponentRegistry.register("\(type)", …). Known types: \(known.joined(separator: ", "))
            """
        case .cycleDetected:
            return "Flow graph contains a cycle; cannot topologically order it."
        case .noLLMProvider(let node):
            return "No LLM provider resolved for node \(node). Check llm-config.json (default/overrides/providers)."
        }
    }
}

public enum LLMError: Error, CustomStringConvertible {
    case unavailable(String)
    case notImplemented(String)

    public var description: String {
        switch self {
        case .unavailable(let why):    return "LLM unavailable: \(why)"
        case .notImplemented(let why): return "LLM backend not wired: \(why)"
        }
    }
}
