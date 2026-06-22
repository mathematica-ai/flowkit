import Foundation

/// Sample flows bundled with FlowKit for the demo, tests, and quick experiments.
///
/// Real apps load their **own** exported Langflow flows instead:
/// ```swift
/// let flow = try FlowParser.parse(url: Bundle.main.url(forResource: "my-flow", withExtension: "json")!)
/// // or: let flow = try FlowParser.parse(data: someData)
/// ```
public enum SampleFlows {
    public static let names = ["hello-world", "prompt-llm"]

    public static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw FlowError.malformed("sample flow \(name).json not found in FlowKit bundle")
        }
        return try Data(contentsOf: url)
    }

    public static func flow(_ name: String) throws -> Flow {
        try FlowParser.parse(data: data(name))
    }

    /// The raw œ-escaped sourceHandle of the first hello-world edge (handy for demoing decoding).
    public static func rawHelloWorldSourceHandle() throws -> String? {
        guard let root = try JSONSerialization.jsonObject(with: data("hello-world")) as? [String: Any],
              let d = root["data"] as? [String: Any],
              let edges = d["edges"] as? [[String: Any]],
              let first = edges.first else { return nil }
        return first["sourceHandle"] as? String
    }
}
