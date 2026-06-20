import Foundation
import NaturalLanguage

/// A document in the on-device knowledge corpus (brand policy, FAQ, statutory text…).
public struct KnowledgeDocument: Sendable, Equatable {
    public let id: String
    public let text: String
    public let metadata: [String: String]
    public init(id: String, text: String, metadata: [String: String] = [:]) {
        self.id = id
        self.text = text
        self.metadata = metadata
    }
}

public struct RetrievedDocument: Sendable, Equatable {
    public let id: String
    public let text: String
    public let score: Double
}

/// On-device retriever — the native replacement for the server "Knowledge 314" brand-policy/legal
/// retriever. Uses Apple's `NLEmbedding` sentence vectors + cosine similarity, with a deterministic
/// lexical-overlap fallback when sentence embeddings are unavailable (so it always works offline).
public struct EmbeddingRetriever: Sendable {
    public let documents: [KnowledgeDocument]
    private let docVectors: [[Double]?]
    private let useEmbeddings: Bool

    public init(documents: [KnowledgeDocument], useEmbeddings: Bool = true) {
        self.documents = documents
        if useEmbeddings, let embedding = NLEmbedding.sentenceEmbedding(for: .english) {
            self.useEmbeddings = true
            self.docVectors = documents.map { embedding.vector(for: $0.text) }
        } else {
            self.useEmbeddings = false
            self.docVectors = Array(repeating: nil, count: documents.count)
        }
    }

    public func search(_ query: String, topK: Int = 3) -> [RetrievedDocument] {
        let scored: [(KnowledgeDocument, Double)]
        if useEmbeddings,
           let embedding = NLEmbedding.sentenceEmbedding(for: .english),
           let queryVector = embedding.vector(for: query) {
            scored = zip(documents, docVectors).map { doc, vector in
                (doc, vector.map { cosineSimilarity(queryVector, $0) } ?? -1)
            }
        } else {
            let queryTokens = tokenize(query)
            scored = documents.map { ($0, lexicalScore(queryTokens, tokenize($0.text))) }
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { RetrievedDocument(id: $0.0.id, text: $0.0.text, score: $0.1) }
    }

    /// Tiered retrieval (brand-specific → category → statutory), de-duplicated by id —
    /// mirrors the server retriever's query ladder.
    public func searchTiered(_ queries: [String], perTier: Int = 2) -> [RetrievedDocument] {
        var seen = Set<String>()
        var results: [RetrievedDocument] = []
        for query in queries {
            for hit in search(query, topK: perTier) where !seen.contains(hit.id) {
                seen.insert(hit.id)
                results.append(hit)
            }
        }
        return results
    }
}

/// Exposes a retriever to an agent as a `LangflowTool`.
public struct RetrieverTool: LangflowTool {
    public let name: String
    public let description: String
    private let retriever: EmbeddingRetriever
    private let topK: Int

    public init(name: String = "knowledge_retriever",
                description: String = "Search bundled brand-policy and legal documents for text relevant to a query.",
                retriever: EmbeddingRetriever,
                topK: Int = 3) {
        self.name = name
        self.description = description
        self.retriever = retriever
        self.topK = topK
    }

    public func call(_ input: String) async throws -> String {
        let hits = retriever.search(input, topK: topK)
        guard !hits.isEmpty else { return "No relevant documents found." }
        return hits.map { "[\($0.id)] \($0.text)" }.joined(separator: "\n\n")
    }
}

// MARK: - Scoring helpers

private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return -1 }
    var dot = 0.0, na = 0.0, nb = 0.0
    for i in a.indices {
        dot += a[i] * b[i]
        na += a[i] * a[i]
        nb += b[i] * b[i]
    }
    let denom = (na.squareRoot() * nb.squareRoot())
    return denom == 0 ? -1 : dot / denom
}

private func tokenize(_ text: String) -> Set<String> {
    Set(text.lowercased()
        .split { !$0.isLetter && !$0.isNumber }
        .map(String.init)
        .filter { $0.count > 2 })
}

private func lexicalScore(_ query: Set<String>, _ doc: Set<String>) -> Double {
    guard !query.isEmpty, !doc.isEmpty else { return 0 }
    let overlap = query.intersection(doc).count
    return Double(overlap) / (Double(query.count).squareRoot() * Double(doc.count).squareRoot())
}
