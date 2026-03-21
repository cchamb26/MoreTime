import SwiftUI

struct DebugLogView: View {
    private let logger = ErrorLogger.shared

    var body: some View {
        NavigationStack {
            Group {
                if logger.entries.isEmpty {
                    ContentUnavailableView {
                        Label("No Logs", systemImage: "doc.text")
                    } description: {
                        Text("Errors and warnings will appear here")
                    }
                } else {
                    List(logger.entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: entry.level == .error ? "xmark.circle.fill" :
                                        entry.level == .warning ? "exclamationmark.circle.fill" : "info.circle.fill")
                                    .foregroundStyle(entry.level == .error ? .red : entry.level == .warning ? .orange : .blue)
                                    .font(.caption)

                                Text("[\(entry.source)] \(entry.operation)")
                                    .font(.caption.monospaced().weight(.semibold))

                                Spacer()

                                Text(Self.timeFormatter.string(from: entry.timestamp))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }

                            Text(entry.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Error Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !logger.entries.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear") { logger.clearLog() }
                    }
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
