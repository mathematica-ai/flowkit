import XCTest
@testable import FlowKit

final class HandleDecodeTests: XCTestCase {
    func testDecodesEscapedSourceHandle() {
        let raw = "{œdataTypeœ:œTextInputœ,œidœ:œTextInput-J1CQKœ,œnameœ:œtextœ,œoutput_typesœ:[œMessageœ]}"
        let obj = FlowParser.decodeEscapedHandle(raw)
        XCTAssertEqual(obj?["name"] as? String, "text")
        XCTAssertEqual(obj?["dataType"] as? String, "TextInput")
        XCTAssertEqual(obj?["output_types"] as? [String], ["Message"])
    }

    func testDecodesEscapedTargetHandle() {
        let raw = "{œfieldNameœ:œinput_valueœ,œidœ:œChatOutput-boh63œ,œtypeœ:œotherœ}"
        let obj = FlowParser.decodeEscapedHandle(raw)
        XCTAssertEqual(obj?["fieldName"] as? String, "input_value")
    }
}

final class FlowParserTests: XCTestCase {
    func testParsesRealHelloWorldExport() throws {
        let flow = try SampleFlows.flow("hello-world")
        XCTAssertEqual(flow.nodes.count, 2)
        XCTAssertEqual(Set(flow.nodes.map(\.type)), ["TextInput", "ChatOutput"])

        let textInput = try XCTUnwrap(flow.nodes.first { $0.type == "TextInput" })
        XCTAssertEqual(textInput.template["input_value"]?.value?.asText, "Hello, World!")
        XCTAssertNil(textInput.template["code"])   // Python source dropped

        let edge = try XCTUnwrap(flow.edges.first)
        XCTAssertEqual(edge.sourceOutput, "text")
        XCTAssertEqual(edge.targetField, "input_value")
    }
}

final class ExecutorTests: XCTestCase {
    private func echoEngine() -> FlowEngine { FlowEngine(config: .echoOnly) }

    func testRunsHelloWorldEndToEnd() async throws {
        let flow = try SampleFlows.flow("hello-world")
        let result = try await echoEngine().run(flow)
        XCTAssertEqual(result.terminalMessages.first?.message.text, "Hello, World!")
    }

    func testRunsPromptThenLLMChain() async throws {
        let flow = try SampleFlows.flow("prompt-llm")
        let output = try await echoEngine().reply("What is the capital of France?", flow: flow)
        XCTAssertTrue(output.contains("Answer in one short sentence. Question: What is the capital of France?"),
                      "unexpected output: \(output)")
        XCTAssertTrue(output.contains("You asked"), "echo provider not used: \(output)")
    }

    func testUnknownComponentFailsLoudly() async {
        let flow = Flow(
            nodes: [FlowNode(id: "Mystery-1", type: "MysteryComponent", displayName: nil,
                             template: [:], outputs: [])],
            edges: []
        )
        do {
            _ = try await echoEngine().run(flow)
            XCTFail("expected unknownComponent error")
        } catch let error as FlowError {
            guard case .unknownComponent(let type, _, _) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(type, "MysteryComponent")
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}

final class ExtensibilityTests: XCTestCase {
    /// A host app can plug in its own LLM backend by name — no fork needed.
    struct StubProvider: LLMProvider {
        func generate(system: String?, user: String) async throws -> String { "STUB:\(user)" }
    }

    func testCustomProviderOverridesByName() async throws {
        let config = LLMConfig(defaultProvider: "mine", overrides: [:],
                               providers: ["mine": .init(backend: "openai")])   // backend stub…
        let engine = FlowEngine(config: config, providers: ["mine": StubProvider()])  // …overridden here
        let flow = try SampleFlows.flow("prompt-llm")
        let output = try await engine.reply("ping", flow: flow)
        XCTAssertTrue(output.hasPrefix("STUB:"), "custom provider not used: \(output)")
    }

    /// A host app can register its own 1:1 component implementation.
    struct ShoutComponent: Component {
        func run(_ ctx: ComponentContext) async throws -> [String: FlowValue] {
            ["text": .message(Message(text: (ctx.inputs["input_value"]?.asText ?? "").uppercased()))]
        }
    }

    func testCustomComponentRegistration() async throws {
        var registry = ComponentRegistry.standard()
        registry.register("Shout", ShoutComponent())
        let engine = FlowEngine(config: .echoOnly, registry: registry)

        let flow = Flow(
            nodes: [
                FlowNode(id: "Shout-1", type: "Shout", displayName: nil,
                         template: ["input_value": TemplateField(value: .text("quiet"), valueType: "str", inputTypes: [])],
                         outputs: [NodeOutput(name: "text", types: ["Message"])]),
                FlowNode(id: "ChatOutput-1", type: "ChatOutput", displayName: nil,
                         template: [:], outputs: [NodeOutput(name: "message", types: ["Message"])]),
            ],
            edges: [FlowEdge(source: "Shout-1", target: "ChatOutput-1",
                             sourceOutput: "text", targetField: "input_value")]
        )
        let result = try await engine.run(flow)
        XCTAssertEqual(result.terminalMessages.first?.message.text, "QUIET")
    }
}
