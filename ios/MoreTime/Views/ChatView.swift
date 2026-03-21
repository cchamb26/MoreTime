import SwiftUI

struct ChatView: View {
    @Environment(ChatStore.self) private var chatStore
    @State private var inputText = ""
    @State private var showVoice = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if chatStore.messages.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "message")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.secondary.opacity(0.5))

                                    Text("Ask me anything about your schedule")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 6) {
                                        SuggestionChip("What should I work on today?")
                                        SuggestionChip("I have a CS310 project due next Friday")
                                        SuggestionChip("How much time do I have left this week?")
                                    }
                                }
                                .padding(.top, 80)
                            }

                            ForEach(chatStore.messages) { bubble in
                                ChatBubbleView(bubble: bubble)
                                    .id(bubble.id)
                            }

                            if chatStore.isLoading {
                                HStack {
                                    TypingIndicator()
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .id("typing")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: chatStore.messages.count) {
                        withAnimation {
                            proxy.scrollTo(chatStore.messages.last.map { $0.id as AnyHashable } ?? ("typing" as AnyHashable), anchor: .bottom)
                        }
                    }
                }

                Divider()

                // Input bar
                HStack(spacing: 12) {
                    Button {
                        showVoice = true
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Message", text: $inputText, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .onSubmit { send() }

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(inputText.isEmpty ? .secondary : .primary)
                    }
                    .disabled(inputText.isEmpty || chatStore.isLoading)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Button("New Chat") {
                        chatStore.clearSession()
                    }
                }
            }
            .sheet(isPresented: $showVoice) {
                VoiceInputView()
            }
        }
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await chatStore.sendMessage(text) }
    }
}

struct ChatBubbleView: View {
    let bubble: ChatBubble

    var body: some View {
        HStack {
            if bubble.role == "user" { Spacer(minLength: 60) }

            Text(bubble.content)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(bubble.role == "user" ? Color(.systemBackground) : Color.primary)
                .background(bubble.role == "user" ? Color.primary : Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))

            if bubble.role == "assistant" { Spacer(minLength: 60) }
        }
    }
}

struct SuggestionChip: View {
    @Environment(ChatStore.self) private var chatStore
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Button {
            Task { await chatStore.sendMessage(text) }
        } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.gray.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
                    .offset(y: sin(phase + Double(i) * 0.8) * 3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
