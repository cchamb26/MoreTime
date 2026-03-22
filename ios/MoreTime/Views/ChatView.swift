import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var inputText = ""
    @State private var showVoice = false
    @State private var isFileImporterPresented = false
    @FocusState private var isInputFocused: Bool

    private var canSend: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let completed = chatStore.pendingAttachmentFiles.filter { $0.parseStatus == "completed" }
        let parsing = chatStore.pendingAttachmentFiles.contains {
            $0.parseStatus == "pending" || $0.parseStatus == "parsing"
        }
        let failed = chatStore.pendingAttachmentFiles.contains { $0.parseStatus == "failed" }

        if chatStore.isLoading || chatStore.isPreparingAttachments { return false }
        if parsing || failed { return false }
        if !trimmed.isEmpty { return true }
        return !completed.isEmpty
    }

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

                if !chatStore.pendingAttachmentFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chatStore.pendingAttachmentFiles) { file in
                                ChatPendingAttachmentChip(file: file) {
                                    chatStore.removePendingAttachment(id: file.id)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }
                    .background(.bar.opacity(0.5))
                }

                // Input bar
                HStack(spacing: 12) {
                    Button {
                        showVoice = true
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(chatStore.isLoading || chatStore.isPreparingAttachments)

                    TextField("Message", text: $inputText, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .onSubmit { send() }

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(canSend ? .primary : .secondary)
                    }
                    .disabled(!canSend)
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
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.pdf, .plainText, .png, .jpeg,
                    UTType(filenameExtension: "docx") ?? .data],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                Task { await chatStore.addAttachments(from: urls) }
            }
            .overlay {
                if chatStore.isPreparingAttachments {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                    ProgressView("Uploading…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func send() {
        guard canSend else { return }
        let text = inputText
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

    private var trimmedContent: String {
        bubble.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack {
            if bubble.role == "user" { Spacer(minLength: 60) }

            Group {
                if bubble.role == "user" {
                    VStack(alignment: .trailing, spacing: 8) {
                        if !bubble.attachmentNames.isEmpty {
                            VStack(alignment: .trailing, spacing: 4) {
                                ForEach(bubble.attachmentNames, id: \.self) { name in
                                    Label(name, systemImage: "doc.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color(.systemBackground).opacity(0.9))
                                }
                            }
                        }
                        if !trimmedContent.isEmpty {
                            Text(bubble.content)
                                .font(.subheadline)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color(.systemBackground))
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    Text(bubble.content)
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(Color.primary)
                        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                }
            }

            if bubble.role == "assistant" { Spacer(minLength: 60) }
        }
    }
}

private struct ChatPendingAttachmentChip: View {
    let file: FileUploadResponse
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .font(.caption)
            Text(file.originalName)
                .font(.caption)
                .lineLimit(1)
            if file.parseStatus == "pending" || file.parseStatus == "parsing" {
                ProgressView()
                    .scaleEffect(0.7)
            } else if file.parseStatus == "failed" {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.gray.opacity(0.15), in: Capsule())
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
