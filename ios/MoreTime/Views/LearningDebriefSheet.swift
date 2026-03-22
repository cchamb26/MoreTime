import SwiftUI

/// Shown after marking a task complete; saves an optional reflection into profile preferences for chat context.
struct LearningDebriefSheet: View {
    @Environment(AuthStore.self) private var authStore

    let taskId: String
    let taskTitle: String
    /// Called after Skip or after a successful Save (caller may dismiss parent navigation).
    var onFinished: () -> Void

    @State private var confidence = 3
    @State private var blockerKind: BlockerKind = .time
    @State private var otherDetail = ""
    @State private var revisit = ""
    @State private var isSaving = false
    @State private var saveError: String?

    private enum BlockerKind: String, CaseIterable, Identifiable {
        case time
        case understanding
        case motivation
        case other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .time: return "Ran out of time"
            case .understanding: return "Didn't fully understand the material"
            case .motivation: return "Hard to stay motivated"
            case .other: return "Something else"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(taskTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("You completed")
                }

                Section("How confident do you feel about this work?") {
                    Picker("Confidence", selection: $confidence) {
                        ForEach(1...5, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(confidenceCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("What was the hardest part?") {
                    Picker("Blocker", selection: $blockerKind) {
                        ForEach(BlockerKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)

                    if blockerKind == .other {
                        TextField("Describe briefly", text: $otherDetail, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }

                Section("Anything to revisit later? (optional)") {
                    TextField("e.g. Chapter 7 problems", text: $revisit, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Quick reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onFinished()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveDebrief() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var confidenceCaption: String {
        switch confidence {
        case 1: return "Not confident"
        case 2: return "Somewhat shaky"
        case 3: return "Okay"
        case 4: return "Fairly confident"
        default: return "Very confident"
        }
    }

    private func blockerPayload() -> String {
        switch blockerKind {
        case .time: return "time"
        case .understanding: return "understanding"
        case .motivation: return "motivation"
        case .other:
            let t = otherDetail.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return "other" }
            return String(t.prefix(80))
        }
    }

    private func saveDebrief() async {
        isSaving = true
        defer { isSaving = false }

        let ok = await authStore.appendLearningDebrief(
            taskId: taskId,
            title: taskTitle,
            confidence: confidence,
            blocker: blockerPayload(),
            revisit: revisit.isEmpty ? nil : revisit,
        )
        if ok {
            saveError = nil
            onFinished()
        } else {
            saveError = authStore.error ?? "Couldn't save reflection."
        }
    }
}
