import Foundation

// Apple's on-device LLM ("Siri AI" / Apple Intelligence) via the Foundation Models framework.
// Runs 100% on-device, free and private, on Apple-Intelligence hardware (iPhone 15 Pro / 16+,
// M-series Macs/iPads) running macOS/iOS 26+.

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
public struct FoundationModelsProvider: LLMProvider {
    public init() {}

    public func generate(system: String?, user: String) async throws -> String {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw LLMError.unavailable("Apple Intelligence model not ready (\(reason))")
        @unknown default:
            throw LLMError.unavailable("Apple Intelligence model not ready")
        }

        let session: LanguageModelSession
        if let system {
            session = LanguageModelSession(instructions: system)
        } else {
            session = LanguageModelSession()
        }
        let response = try await session.respond(to: user)
        return response.content
    }
}

#else

// Fallback so the type always exists (e.g. building against an SDK without Foundation Models).
@available(macOS 26.0, iOS 26.0, *)
public struct FoundationModelsProvider: LLMProvider {
    public init() {}
    public func generate(system: String?, user: String) async throws -> String {
        throw LLMError.unavailable("Foundation Models framework not available in this SDK")
    }
}

#endif
