import Foundation

/// A tool an agent can invoke during a flow run (the on-device analogue of a Langflow tool node:
/// knowledge retriever, OCR, damage detection, ask-a-human…).
///
/// Kept deliberately simple — string in, string out — so any concrete tool (RAG, Vision OCR, a
/// reused on-device classifier) conforms, and so it bridges cleanly to Apple Foundation Models'
/// tool-calling. Binary/ambient inputs (images, attachments) are captured by the concrete tool.
public protocol LangflowTool: Sendable {
    var name: String { get }
    var description: String { get }
    func call(_ input: String) async throws -> String
}
