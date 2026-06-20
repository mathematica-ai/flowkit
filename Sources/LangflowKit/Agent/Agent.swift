import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Bridges a `LangflowTool` (string in/out) to Apple Foundation Models' `Tool` protocol so the
/// on-device model can call it during a tool-calling loop.
@available(macOS 26.0, iOS 26.0, *)
struct BridgedTool: FoundationModels.Tool {
    let backing: any LangflowTool

    var name: String { backing.name }
    var description: String { backing.description }

    @Generable
    struct Arguments {
        @Guide(description: "The query or input to pass to the tool")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        try await backing.call(arguments.query)
    }
}

/// On-device agent: runs an Apple Foundation Models tool-calling loop over LangflowKit tools.
/// The native analogue of the Langflow `Agent` node — the model decides which tools to call
/// (knowledge retriever, OCR, …) before producing its answer.
@available(macOS 26.0, iOS 26.0, *)
public struct Agent {
    public let instructions: String
    public let tools: [any LangflowTool]

    public init(instructions: String, tools: [any LangflowTool] = []) {
        self.instructions = instructions
        self.tools = tools
    }

    private func makeSession() -> LanguageModelSession {
        let bridged: [any FoundationModels.Tool] = tools.map { BridgedTool(backing: $0) }
        return LanguageModelSession(tools: bridged, instructions: instructions)
    }

    /// Free-text answer after the model has (optionally) called tools.
    public func run(_ input: String) async throws -> String {
        try await makeSession().respond(to: input).content
    }

    /// Guided generation: the model produces a typed `@Generable` result (e.g. a triage struct)
    /// after using its tools. This is how the app gets structured output on-device.
    public func run<T: Generable>(_ input: String, generating type: T.Type) async throws -> T {
        try await makeSession().respond(to: input, generating: type).content
    }
}
#endif
