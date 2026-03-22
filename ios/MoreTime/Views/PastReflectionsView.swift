import SwiftUI

struct PastReflectionsView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var showClearConfirm = false

    private static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var entries: [LearningDebriefEntry] {
        authStore.learningDebriefEntries()
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No reflections yet", systemImage: "text.quote")
                } description: {
                    Text("When you complete a task and save a quick reflection, it appears here. The assistant also uses these in Chat.")
                }
            } else {
                List {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.taskTitle)
                                .font(.headline)
                                .lineLimit(3)

                            if let d = entry.recordedAt {
                                Text(Self.mediumDate.string(from: d))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if !entry.atISO.isEmpty {
                                Text(entry.atISO)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            LabeledContent("Confidence") {
                                Text("\(entry.confidence) / 5")
                            }
                            .font(.subheadline)

                            LabeledContent("Hardest part") {
                                Text(entry.blockerDisplayLabel)
                            }
                            .font(.subheadline)

                            if !entry.revisit.isEmpty {
                                LabeledContent("Revisit") {
                                    Text(entry.revisit)
                                }
                                .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Past reflections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear all", role: .destructive) {
                        showClearConfirm = true
                    }
                }
            }
        }
        .alert("Clear all reflections?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    _ = await authStore.clearLearningDebriefs()
                }
            }
        } message: {
            Text("This removes saved debriefs from your profile. Chat will no longer see them in context.")
        }
        .task {
            await authStore.fetchProfile()
        }
        .refreshable {
            await authStore.fetchProfile()
        }
    }
}
