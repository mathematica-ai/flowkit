import XCTest
@testable import LangflowKit

final class RetrieverTests: XCTestCase {
    private let corpus = [
        KnowledgeDocument(id: "maje-policy",
            text: "Maje offers a 30 day return for manufacturing defects in France. Normal wear and tear is excluded from the warranty."),
        KnowledgeDocument(id: "loropiana-policy",
            text: "Loro Piana cashmere garments are covered by a repair service for pilling and seam issues."),
        KnowledgeDocument(id: "store-hours",
            text: "Store opening hours are nine in the morning to six in the evening on weekdays."),
    ]

    func testLexicalRetrievalRanksRelevantDoc() {
        let retriever = EmbeddingRetriever(documents: corpus, useEmbeddings: false)
        let hits = retriever.search("Maje manufacturing defect return France", topK: 1)
        XCTAssertEqual(hits.first?.id, "maje-policy")
    }

    func testTieredRetrievalDeduplicates() {
        let retriever = EmbeddingRetriever(documents: corpus, useEmbeddings: false)
        let hits = retriever.searchTiered([
            "Maje manufacturing defect",        // brand-specific
            "France manufacturing warranty",    // category
            "consumer guarantee France",        // statutory-ish
        ], perTier: 2)
        let ids = hits.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "results should be de-duplicated")
        XCTAssertTrue(ids.contains("maje-policy"))
    }

    func testRetrieverToolReturnsText() async throws {
        let tool = RetrieverTool(retriever: EmbeddingRetriever(documents: corpus, useEmbeddings: false))
        let out = try await tool.call("Maje defect return")
        XCTAssertTrue(out.contains("Maje"), "expected Maje policy in: \(out)")
        XCTAssertEqual(tool.name, "knowledge_retriever")
    }

    func testEmbeddingPathReturnsResultsOrFallsBack() {
        // With embeddings on, it should still return ranked results (or gracefully fall back).
        let retriever = EmbeddingRetriever(documents: corpus, useEmbeddings: true)
        let hits = retriever.search("cashmere repair pilling", topK: 2)
        XCTAssertFalse(hits.isEmpty)
    }
}
