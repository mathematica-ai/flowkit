# FlowKit

> Run **Langflow** and **n8n** AI workflows 100% on-device on Apple — native Swift, no server, no Python, no Node.

_Unofficial. Not affiliated with or endorsed by Langflow / DataStax / n8n._

FlowKit takes a visual workflow you designed in [Langflow](https://github.com/langflow-ai/langflow) or
[n8n](https://github.com/n8n-io/n8n), exports the JSON, and **executes it on-device**. One engine
underneath (a name-keyed component registry + a topological DAG executor + a config-bound LLM slot
backed by Apple Foundation Models); a small per-format **front-end** turns each tool's export into the
shared `Flow` model. No server, no Python/Node, and — with the on-device model — no network.

You **design** the flow in Langflow as it exists today, **export** the JSON, and a native Swift
runtime **executes** it by mapping each component to a 1:1 Swift implementation. The LLM (and other
external resources) are chosen at runtime from a config file — so "on-device with Apple Foundation
Models" vs "cloud API" is a config toggle, not a rebuild.

> Status: **working proof-of-concept.** Parses a real Langflow export, walks the DAG, and runs an
> LLM step on Apple's on-device model. Built & tested on Swift 6.3 / Xcode 26, and verified consumable
> from a separate package.

## Add it to your app

The `FlowKit` library product is what you depend on. Three ways to add it:

**Xcode (recommended):** File → Add Package Dependencies → enter the repo URL *or* "Add Local…" and
pick this folder → check the **FlowKit** library → add to your app target.

**Package.swift, by git tag:**
```swift
dependencies: [
    .package(url: "https://github.com/mathematica-ai/flowkit.git", from: "0.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "FlowKit", package: "flowkit"),  // identity = repo name
    ]),
]
```

**Package.swift, local path (no git needed):**
```swift
.package(path: "../flowkit"),
// then: .product(name: "FlowKit", package: "flowkit")
```

> The package identity is the **repo name** (`flowkit`), while the library/module you import is
> `FlowKit` — that's the split between `.product(package:)` and `.product(name:)`.

## Use it from your app

```swift
import FlowKit

// 1. pick a backend (on-device, offline, or your own — see below)
let engine = FlowEngine(config: .appleOnDevice)   // or .echoOnly

// 2. load YOUR exported Langflow flow
let url  = Bundle.main.url(forResource: "my-flow", withExtension: "json")!
let flow = try FlowParser.parse(url: url)

// 3. run it — inject user input, get the result text
let answer = try await engine.reply("What's the capital of France?", flow: flow)
```

`engine.run(flow, input:overrides:)` returns the full `ExecutionResult` (every node's outputs +
terminal messages) when you need more than the final text.

### Plug in your own LLM backend (no fork)

`echo` and `foundation_models` are built in; `openai`/`anthropic` are stubs. Inject a real provider
by name — it overrides the built-in factory:

```swift
struct MyOpenAI: LLMProvider {
    func generate(system: String?, user: String) async throws -> String { /* call your SDK */ }
}
let config = LLMConfig(defaultProvider: "gpt", overrides: [:],
                       providers: ["gpt": .init(backend: "openai", model: "gpt-5")])
let engine = FlowEngine(config: config, providers: ["gpt": MyOpenAI()])
```

### Register your own component

```swift
struct MyComponent: Component {
    func run(_ ctx: ComponentContext) async throws -> [String: FlowValue] {
        ["output_name": .text((ctx.inputs["some_field"]?.asText ?? "").uppercased())]
    }
}
var registry = ComponentRegistry.standard()
registry.register("MyLangflowTypeName", MyComponent())   // keyed 1:1 by Langflow data.type
let engine = FlowEngine(config: .appleOnDevice, registry: registry)
```

## Two engines, one runtime: n8n

n8n workflows are the same shape — a JSON graph of typed nodes + connections — so they run on the
same executor. The only per-engine pieces are a parser and a node-type registry:

```swift
let flow = try N8nWorkflowParser.parse(url: myN8nExportURL)   // n8n JSON → shared Flow
let executor = Executor(registry: .n8nStandard(),            // n8n node types → Swift impls
                        services: Services(llm: .from(config: .appleOnDevice)))
let result = try await executor.run(flow)                    // trigger → Set → LLM, on-device
```

- **`N8nWorkflowParser`** maps n8n `nodes`/`connections` into the shared `Flow`.
- **`ComponentRegistry.n8nStandard()`** ships a starter set: `manualTrigger`, `set`/`editFields`,
  `noOp`, and an LLM/agent node routed to the same on-device `LLMProvider`.
- **n8n expressions** (`={{ $json.field }}`) are evaluated on-device with **JavaScriptCore** (Apple's
  built-in JS engine — App-Store-safe; no downloaded code).

Scope note: most n8n nodes are *integrations* (HTTP/Slack/DB) that inherently hit the network — those
are out of scope for an offline runner. FlowKit targets the **AI + logic subset** (LLM/agent + item
logic), exactly as it targets Langflow's LLM/agent components.

## On-device agent, RAG & OCR

Beyond plain DAG flows, FlowKit ships the pieces an *agentic* flow needs — all on-device:

- `Agent` — an Apple Foundation Models tool-calling loop (native analogue of a Langflow `Agent` node). Give it instructions + tools; the model decides what to call.
- `LangflowTool` — string-in/string-out tool protocol; any capability conforms.
- `EmbeddingRetriever` / `RetrieverTool` — on-device RAG (NaturalLanguage sentence embeddings + cosine, with a deterministic lexical fallback) over a bundled corpus, with tiered queries.
- `VisionOCRTool` — receipt/document OCR via Apple Vision.
- `Agent.run(_:generating:)` — guided generation into a `@Generable` type for structured output.

```swift
let retriever = RetrieverTool(retriever: EmbeddingRetriever(documents: policyDocs))
let ocr = VisionOCRTool(images: receiptImageData)
let agent = Agent(
    instructions: "You triage customer complaints. Use the tools to ground every decision.",
    tools: [retriever, ocr]
)
let triage = try await agent.run(complaintText, generating: ComplaintTriage.self)  // @Generable
```

The `Agent` requires iOS/macOS 26 (Apple Foundation Models); the retriever and OCR work on iOS 14+/macOS 11+.

## Why this shape (and not "port Langflow")

Langflow's runtime is Python: it executes a flow by `exec()`-compiling each node's embedded Python
source (`template.code`), and most components are welded to LangChain. None of that runs on iOS. But
the exported JSON *also* carries everything a native runner needs declaratively: each node's
**`data.type`** (the component class name) and a **`template`** of typed inputs, wired by **edges**.

So we ignore `template.code` and resolve `data.type` against a native registry. Re-implementing
arbitrary exports = re-porting Langflow; implementing a **known set of component types** = a bounded,
shippable project. This is that project, kept small.

## Architecture

```
Design in Langflow ──► export JSON ──► FlowParser ──► Executor ──► outputs
                                          │              │
                              data.type ──┘              ├── ComponentRegistry  (name → Swift impl, 1:1)
                              ignore code                └── Services.llm        (config-bound backend)
```

| Layer | File | Role |
|---|---|---|
| Models | `Core/Models.swift` | `Message`, `FlowValue`, parsed `Flow`/`FlowNode`/`FlowEdge` |
| Parser | `Core/FlowParser.swift` | JSON → `Flow`; keys on `data.type`; decodes `œ`-escaped edge handles |
| Registry | `Core/Component.swift` | `Component` protocol + `ComponentRegistry` (name → implementation) |
| Executor | `Core/Executor.swift` | topological DAG walk, edge value passing, terminal capture |
| Components | `Components/Components.swift` | `TextInput`, `ChatInput`, `Prompt`, `ChatOutput`, `LanguageModel` |
| LLM | `LLM/LLM.swift`, `LLM/FoundationModelsProvider.swift` | `LLMProvider` + config + backends |

### The component registry is 1:1 by name

`data.type` (`"TextInput"`, `"ChatOutput"`, …) is the lookup key. Provider-specific model
components (`OpenAIModel`, `AnthropicModel`, …) deliberately collapse onto one abstract
`LanguageModel` slot — the backend is then chosen by config. Unknown components **fail loudly**,
naming the missing type (the registry doubles as your supported-components manifest).

### LLM by config, not baked into the flow

The model node is an abstract slot resolved at runtime by `LLMConfig` — in code (`.appleOnDevice`,
`.echoOnly`, or your own) or decoded from JSON you ship. `echo` and `foundation_models` are
implemented; `openai`/`anthropic` are clearly-stubbed seams you fill via `providers:` (see
[Plug in your own LLM backend](#plug-in-your-own-llm-backend-no-fork)). For **100% offline**, use
`foundation_models` (or a bundled MLX/llama.cpp model behind the same `LLMProvider` protocol). The
equivalent JSON shape, if you prefer to ship config as a file and `JSONDecoder().decode(LLMConfig.self, …)`:

```jsonc
{
  "default": "siri",
  "overrides": { "OpenAIModel-ab12": "claude" },   // optionally pin one node
  "providers": {
    "siri":   { "backend": "foundation_models" },  // Apple on-device LLM (free, private)
    "echo":   { "backend": "echo" },
    "gpt":    { "backend": "openai",    "model": "gpt-5",           "keyRef": "keychain:openai" }
  }
}
```

## Run the bundled demos

```bash
swift test                     # 15 tests: parser, executor, extensibility, retriever, OCR, agent
swift run runflow              # both sample flows, offline "echo" backend
swift run runflow --llm siri   # routes the LLM slot to Apple Foundation Models (iOS/macOS 26 + Apple Intelligence)
```

`swift run runflow --llm siri` produces, fully on-device:

```
── prompt-llm.json (Prompt → LanguageModel) ────────
   graph: ChatInput → Prompt → LanguageModel → ChatOutput
   output [ChatOutput-1]: The capital of France is Paris.
```

`Sources/FlowKit/Resources/hello-world.json` is a **real** Langflow export; `prompt-llm.json` is
a minimal hand-authored flow in the same shape exercising the config-bound LLM.

## Demo app (SwiftUI)

A small cross-platform SwiftUI chat app drives the same engine: pick a flow, pick the LLM backend
(`Echo · offline` or `Apple · on-device`), type, and watch the flow run.

```bash
swift run LangflowDemo          # launches the macOS app (Swift 6 / Xcode 26)
```

- `Sources/LangflowDemo/ChatViewModel.swift` — `@Observable @MainActor` model; resolves the backend
  from the picker and runs the flow via `FlowEngine.reply(_:flow:)`. It consumes `FlowKit` exactly
  as any other app would.
- `Sources/LangflowDemo/ContentView.swift` — idiomatic SwiftUI: `@State` model, `ScrollViewReader`
  auto-scroll, segmented backend picker, message bubbles.

The views are platform-neutral, so to run on **iPhone/iPad**: create an iOS App in Xcode, add this
package, set `ContentView()` as the root, and select `Apple · on-device` on an Apple-Intelligence
device (iOS 26+) for a fully offline run.

## License

[Apache License 2.0](LICENSE). FlowKit is unofficial and not affiliated with Langflow / DataStax — see [NOTICE](NOTICE).

## Next steps

- More components (Memory, Router/Conditional, Embeddings, Vector Store/Retriever via VecturaKit, tools/data loaders).
- Bundled-model backends (MLX / llama.cpp) behind `LLMProvider` for larger offline models.
- Streaming outputs (`AsyncStream`) and parallel execution of independent DAG branches.
- A SwiftUI canvas (AudioKit/Flow or swift-flow) if you later want to author flows on-device too.
- Pin a Langflow version and snapshot its component-name set as the registry's compatibility target.
