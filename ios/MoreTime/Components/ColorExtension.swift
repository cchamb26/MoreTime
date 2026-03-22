import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        case 8:
            r = Double((int >> 24) & 0xFF) / 255
            g = Double((int >> 16) & 0xFF) / 255
            b = Double((int >> 8) & 0xFF) / 255
        default:
            r = 0.42; g = 0.44; b = 0.50
        }

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Task priority (labels + colors)

/// Maps numeric API priority (1…5) to short UI labels and accent colors.
enum TaskPriorityUI {
    static func label(for priority: Int) -> String {
        switch priority {
        case 1: return "High"
        case 2: return "Medium"
        case 3, 4, 5: return "Low"
        default: return "Low"
        }
    }

    static func color(for priority: Int) -> Color {
        switch priority {
        case 1: return .red
        case 2: return Color(red: 0.88, green: 0.72, blue: 0.08)
        case 3: return .green
        case 4, 5: return .gray
        default: return .gray
        }
    }
}
