import SwiftUI
import FlowKit

struct ContentView: View {
    @State private var model = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            inputBar
        }
        .frame(minWidth: 460, minHeight: 460)
        .onAppear { if model.flow == nil { model.loadFlow() } }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Label("FlowKit", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Spacer()
                Picker("Backend", selection: $model.backend) {
                    ForEach(ChatViewModel.Backend.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
            }
            HStack(spacing: 8) {
                Picker("Flow", selection: $model.selectedFlow) {
                    ForEach(model.availableFlows, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()

                if !model.componentChain.isEmpty {
                    Text(model.componentChain)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(12)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.messages) { MessageBubble(message: $0) }
                }
                .padding(12)
            }
            .onChange(of: model.messages.count) {
                guard let last = model.messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask the flow…", text: $model.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(model.isRunning)
                .onSubmit { Task { await model.send() } }

            if model.isRunning {
                ProgressView().controlSize(.small).frame(width: 28)
            } else {
                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(!model.canSend)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(12)
    }
}

struct MessageBubble: View {
    let message: ChatViewModel.ChatMessage

    var body: some View {
        switch message.role {
        case .system:
            Text(message.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .id(message.id)
        case .user:
            row(trailing: true, background: Color.accentColor, foreground: .white)
        case .assistant:
            row(trailing: false, background: Color.secondary.opacity(0.18), foreground: .primary)
        }
    }

    private func row(trailing: Bool, background: Color, foreground: Color) -> some View {
        HStack {
            if trailing { Spacer(minLength: 36) }
            Text(message.text)
                .textSelection(.enabled)
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(background, in: RoundedRectangle(cornerRadius: 14))
            if !trailing { Spacer(minLength: 36) }
        }
        .id(message.id)
    }
}

#Preview {
    ContentView()
}
