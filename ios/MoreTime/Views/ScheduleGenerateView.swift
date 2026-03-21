import SwiftUI

struct ScheduleGenerateView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(\.dismiss) private var dismiss

    @State private var hasGenerated = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if !hasGenerated {
                    preGenerateView
                } else if let result = scheduleStore.lastGenerateResult {
                    postGenerateView(result: result)
                }
            }
            .navigationTitle(hasGenerated ? "Results" : "Generate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(hasGenerated ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private var preGenerateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "wand.and.stars")
                .font(.system(size: 56))
                .foregroundStyle(Color.primary.opacity(0.6))

            Text("Generate Schedule")
                .font(.title2.bold())

            Text("AI will analyze your tasks, deadlines, and availability to create an optimized study plan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 8) {
                InfoRow(label: "Pending tasks", value: "\(pendingTaskCount)")
                InfoRow(label: "Total estimated hours", value: String(format: "%.1fh", totalHours))
                InfoRow(label: "Tasks with deadlines", value: "\(tasksWithDeadlines)")
            }
            .padding()
            .background(.gray.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Spacer()

            if pendingTaskCount == 0 {
                Text("Add some tasks first to generate a schedule")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            generateButton
        }
    }

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            if scheduleStore.isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Generating...")
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                Text("Generate My Schedule")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.primary)
        .foregroundStyle(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .disabled(scheduleStore.isGenerating || pendingTaskCount == 0)
        .padding(.horizontal)
        .padding(.bottom)
    }

    private func postGenerateView(result: GenerateScheduleResponse) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)

                    Text("Schedule Generated")
                        .font(.title3.bold())

                    Text("\(result.blocksCreated) blocks created")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                if result.blocksRemoved > 0 {
                    Text("\(result.blocksRemoved) previous blocks replaced")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                warningsSection(result.warnings)

                if !result.blocks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scheduled Blocks")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        ForEach(result.blocks) { block in
                            ScheduleBlockCard(block: block)
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func warningsSection(_ warnings: [String]) -> some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ForEach(warnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
        }
    }

    private var pendingTaskCount: Int {
        taskStore.tasks.filter { $0.status != "completed" }.count
    }

    private var totalHours: Double {
        taskStore.tasks.filter { $0.status != "completed" }.reduce(0) { $0 + $1.estimatedHours }
    }

    private var tasksWithDeadlines: Int {
        taskStore.tasks.filter { $0.status != "completed" && $0.dueDate != nil }.count
    }

    private func generate() async {
        await scheduleStore.generateSchedule()
        hasGenerated = true
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.medium))
        }
    }
}
