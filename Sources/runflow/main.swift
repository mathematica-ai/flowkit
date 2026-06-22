import Foundation
import FlowKit

// Usage:
//   swift run runflow                 # runs both sample flows with the offline "echo" backend
//   swift run runflow --llm siri      # routes the LLM slot to Apple Foundation Models (on-device)
//   swift run runflow --llm gpt       # (stub) shows config-bound provider selection

func providerName(from args: [String]) -> String? {
    guard let i = args.firstIndex(of: "--llm"), i + 1 < args.count else { return nil }
    switch args[i + 1].lowercased() {
    case "fm", "siri", "apple", "foundation_models": return "siri"
    case "echo":                                      return "echo"
    case "gpt", "openai":                             return "gpt"
    case "claude", "anthropic":                       return "claude"
    case let other:                                   return other
    }
}

func demoConfig(args: [String]) -> LLMConfig {
    let providers: [String: LLMConfig.ProviderSpec] = [
        "echo":   .init(backend: "echo"),
        "siri":   .init(backend: "foundation_models"),
        "gpt":    .init(backend: "openai",    model: "gpt-5",            keyRef: "keychain:openai"),
        "claude": .init(backend: "anthropic", model: "claude-opus-4-8",  keyRef: "keychain:anthropic"),
    ]
    return LLMConfig(defaultProvider: providerName(from: args) ?? "echo",
                     overrides: [:], providers: providers)
}

let args = CommandLine.arguments
let config = demoConfig(args: args)
let engine = FlowEngine(config: config)

print("FlowKit demo")
print("LLM provider: \(config.defaultProvider)   components: \(ComponentRegistry.standard().registeredTypes.joined(separator: ", "))\n")

// Demonstrate œ-handle decoding on the real export.
if let raw = try? SampleFlows.rawHelloWorldSourceHandle(),
   let decoded = FlowParser.decodeEscapedHandle(raw) {
    print("œ-handle decode (real hello-world edge):")
    print("   raw:     \(raw)")
    print("   decoded: name=\(decoded["name"] ?? "?")\n")
}

for name in SampleFlows.names {
    do {
        let flow = try SampleFlows.flow(name)
        let result = try await engine.run(flow)
        print("── \(name) " + String(repeating: "─", count: max(0, 44 - name.count)))
        print("   graph: \(flow.nodes.map(\.type).joined(separator: " → "))")
        for terminal in result.terminalMessages {
            print("   output [\(terminal.nodeId)]: \(terminal.message.text)")
        }
        print("")
    } catch {
        print("\(name) failed: \(error)\n")
    }
}
