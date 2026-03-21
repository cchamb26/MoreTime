import SwiftUI

struct ErrorBanner: ViewModifier {
    let entry: AppLogEntry?
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let entry {
                HStack(spacing: 10) {
                    Image(systemName: iconName(entry.level))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(iconColor(entry.level))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(entry.source)] \(entry.operation)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.caption)
                            .lineLimit(3)
                    }

                    Spacer()

                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: entry?.id)
    }

    private func iconName(_ level: AppLogEntry.Level) -> String {
        switch level {
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func iconColor(_ level: AppLogEntry.Level) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}

extension View {
    func errorBanner(_ entry: AppLogEntry?, onDismiss: @escaping () -> Void) -> some View {
        modifier(ErrorBanner(entry: entry, onDismiss: onDismiss))
    }
}
