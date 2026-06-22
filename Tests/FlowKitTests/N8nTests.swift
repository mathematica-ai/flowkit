import XCTest
@testable import FlowKit

final class N8nParserTests: XCTestCase {
    func testParsesNodesAndConnections() throws {
        let flow = try SampleFlows.n8nWorkflow("n8n-demo")
        XCTAssertEqual(flow.nodes.count, 3)
        XCTAssertEqual(Set(flow.nodes.map(\.type)), [
            "n8n-nodes-base.manualTrigger",
            "n8n-nodes-base.set",
            "@n8n/n8n-nodes-langchain.openAi",
        ])
        // connections key by node name → edges with the "main" conduit
        XCTAssertEqual(flow.edges.count, 2)
        let triggerEdge = try XCTUnwrap(flow.edges.first { $0.source == "When clicking Test" })
        XCTAssertEqual(triggerEdge.target, "Build Prompt")
        XCTAssertEqual(triggerEdge.sourceOutput, "main")
        XCTAssertEqual(triggerEdge.targetField, "main")
    }
}

final class N8nExpressionTests: XCTestCase {
    func testLiteralPassthrough() {
        XCTAssertEqual(N8nExpression.evaluate("plain text", item: .dict([:])).asText, "plain text")
    }

    func testStringInterpolation() {
        let item = FlowValue.dict(["name": .text("World")])
        XCTAssertEqual(N8nExpression.evaluate("=Hello {{ $json.name }}", item: item).asText, "Hello World")
    }

    func testTypedSingleExpression() {
        let item = FlowValue.dict(["count": .number(21)])
        let result = N8nExpression.evaluate("={{ $json.count * 2 }}", item: item)
        XCTAssertEqual(result, .number(42))
    }
}

final class N8nExecutionTests: XCTestCase {
    func testRunsWorkflowEndToEndWithEchoProvider() async throws {
        let flow = try SampleFlows.n8nWorkflow("n8n-demo")
        let executor = Executor(registry: .n8nStandard(),
                                services: Services(llm: .from(config: .echoOnly)))
        let result = try await executor.run(flow)

        // Trigger seed → Set builds "prompt" via {{ $json.complaint }} → LLM consumes it.
        let openAIItem = try XCTUnwrap(result.nodeOutputs["OpenAI"]?["main"]?.asDict)
        let text = try XCTUnwrap(openAIItem["text"]?.asText)
        XCTAssertTrue(text.contains("Maje"), "LLM output should reflect the complaint flowing through Set: \(text)")
        XCTAssertTrue(text.contains("Summarize this customer complaint"),
                      "the n8n expression should have interpolated the prompt: \(text)")
    }
}
