import SwiftUI

struct ChatView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(ScheduleStore.self) private var scheduleStore
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
                                    ResponseEstimator()
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
        Task {
            await chatStore.sendMessage(text)
            if chatStore.lastActionType == "task_created" {
                await taskStore.fetchTasks()
                if chatStore.didGenerateSchedule {
                    // Schedule generates in the background on the server;
                    // poll after a delay so it has time to finish
                    Task.detached {
                        try? await Task.sleep(for: .seconds(10))
                        let now = Date()
                        let cal = Calendar.current
                        let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
                        let end = cal.date(byAdding: .month, value: 1, to: start)!
                        await scheduleStore.fetchBlocks(startDate: start, endDate: end)
                    }
                }
            }
        }
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
    @Environment(TaskStore.self) private var taskStore
    @Environment(ScheduleStore.self) private var scheduleStore
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Button {
            Task {
                await chatStore.sendMessage(text)
                if chatStore.lastActionType == "task_created" {
                    await taskStore.fetchTasks()
                    if chatStore.didGenerateSchedule {
                        Task.detached {
                            try? await Task.sleep(for: .seconds(10))
                            let now = Date()
                            let cal = Calendar.current
                            let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
                            let end = cal.date(byAdding: .month, value: 1, to: start)!
                            await scheduleStore.fetchBlocks(startDate: start, endDate: end)
                        }
                    }
                }
            }
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

struct ResponseEstimator: View {
    @State private var elapsed: TimeInterval = 0
    @State private var shimmerPhase: CGFloat = -1

    private let estimatedSeconds: TimeInterval = 12
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var progress: Double {
        // Asymptotic curve: approaches 1 but never reaches it
        1 - exp(-elapsed / estimatedSeconds * 1.8)
    }

    private var statusText: String {
        switch elapsed {
        case ..<3:    return "Thinking..."
        case ..<8:    return "Analyzing your request..."
        case ..<15:   return "Crafting a response..."
        case ..<25:   return "Almost there..."
        default:      return "Still working on it..."
        }
    }

    private var timeText: String {
        let remaining = max(1, Int(ceil(estimatedSeconds - elapsed)))
        if elapsed >= estimatedSeconds {
            return "any moment now"
        }
        return "~\(remaining)s remaining"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Animated dots
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(.secondary)
                            .frame(width: 5, height: 5)
                            .opacity(dotOpacity(for: i))
                    }
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.gray.opacity(0.15))

                    Capsule()
                        .fill(.primary.opacity(0.5))
                        .frame(width: geo.size.width * progress)

                    // Shimmer
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.3), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.3)
                        .offset(x: geo.size.width * shimmerPhase)
                        .mask(
                            Capsule()
                                .frame(width: geo.size.width * progress)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                }
            }
            .frame(height: 4)

            Text(timeText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .onReceive(timer) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                elapsed += 0.1
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.2
            }
        }
    }

    private func dotOpacity(for index: Int) -> Double {
        let cycle = elapsed.truncatingRemainder(dividingBy: 1.2)
        let start = Double(index) * 0.3
        return (cycle >= start && cycle < start + 0.4) ? 1.0 : 0.35
    }
}
