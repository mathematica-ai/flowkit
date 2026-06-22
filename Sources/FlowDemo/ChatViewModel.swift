import Foundation
import Observation
import FlowKit

@MainActor
@Observable
final class ChatViewModel {

    enum Role: Sendable { case user, assistant, system }

    struct ChatMessage: Identifiable, Sendable {
        let id = UUID()
        let role: Role
        var text: String
    }

    /// The LLM backend the abstract model slot resolves to (config-bound at runtime).
    enum Backend: String, CaseIterable, Identifiable {
        case echo
        case appleOnDevice

        var id: String { rawValue }
        var title: String { self == .echo ? "Echo · offline" : "Apple · on-device" }
        var providerKey: String { self == .echo ? "echo" : "siri" }   // keys into llm-config.json
    }

    let availableFlows = ["prompt-llm", "hello-world"]
    var selectedFlow = "prompt-llm" { didSet { loadFlow() } }
    var backend: Backend = .echo
    var draft = ""
    private(set) var messages: [ChatMessage] = []
    private(set) var isRunning = false
    private(set) var flow: Flow?

    var componentChain: String { flow?.nodes.map(\.type).joined(separator: " → ") ?? "" }

    var canSend: Bool {
        flow != nil && !isRunning && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    func loadFlow() {
        messages.removeAll()
        do {
            let loaded = try SampleFlows.flow(selectedFlow)
            flow = loaded
            messages.append(.init(role: .system,
                                  text: "Loaded \(selectedFlow): \(loaded.nodes.map(\.type).joined(separator: " → "))"))
        } catch {
            flow = nil
            messages.append(.init(role: .system, text: "⚠️ Failed to load \(selectedFlow): \(error)"))
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let flow else { return }
        draft = ""
        messages.append(.init(role: .user, text: text))
        isRunning = true
        defer { isRunning = false }

        do {
            let config: LLMConfig = (backend == .echo) ? .echoOnly : .appleOnDevice
            let engine = FlowEngine(config: config)
            let answer = try await engine.reply(text, flow: flow)
            messages.append(.init(role: .assistant, text: answer.isEmpty ? "(no output)" : answer))
        } catch {
            messages.append(.init(role: .system, text: "⚠️ \(error)"))
        }
    }
}
