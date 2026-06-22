import XCTest
@testable import FlowKit

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
final class AgentTests: XCTestCase {
    func testAgentRunsToolCallingLoopWhenModelAvailable() async throws {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw XCTSkip("Apple Intelligence model unavailable on this machine")
        }

        let corpus = [
            KnowledgeDocument(id: "maje-returns",
                text: "Maje accepts returns within 30 days for manufacturing defects in France."),
        ]
        let tool = RetrieverTool(retriever: EmbeddingRetriever(documents: corpus, useEmbeddings: false))
        let agent = Agent(
            instructions: "You are a returns assistant. Use the knowledge_retriever tool to look up policy facts before answering. Answer concisely.",
            tools: [tool]
        )

        let answer = try await agent.run("How many days do I have to return a defective Maje item in France?")
        XCTAssertFalse(answer.isEmpty, "agent returned empty answer")
    }
}
#endif
