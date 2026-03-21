import Foundation

// MARK: - Auth

struct AuthResponse: Codable {
    let user: UserProfile
    let accessToken: String
    let refreshToken: String
}

struct TokenRefreshResponse: Codable {
    let accessToken: String
    let refreshToken: String
}

struct UserProfile: Codable, Identifiable {
    let id: String
    let email: String
    let name: String
    let timezone: String?
    let preferences: [String: AnyCodable]?
    let createdAt: String?
}

// MARK: - Course

struct Course: Codable, Identifiable {
    let id: String
    var name: String
    var color: String
    var metadata: [String: AnyCodable]?
    let createdAt: String?
    let updatedAt: String?
    var _count: CourseCount?

    struct CourseCount: Codable {
        let tasks: Int
    }
}

struct CreateCourseRequest: Codable {
    let name: String
    let color: String?
    let metadata: [String: AnyCodable]?
}

// MARK: - Task

struct TaskItem: Codable, Identifiable, Hashable {
    let id: String
    var courseId: String?
    var title: String
    var description: String?
    var dueDate: String?
    var priority: Int
    var estimatedHours: Double
    var status: String
    var recurrence: AnyCodable?
    let createdAt: String?
    let updatedAt: String?
    var course: CourseRef?

    struct CourseRef: Codable, Hashable {
        let id: String
        let name: String
        let color: String
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TaskItem, rhs: TaskItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.status == rhs.status &&
        lhs.priority == rhs.priority && lhs.dueDate == rhs.dueDate &&
        lhs.estimatedHours == rhs.estimatedHours && lhs.courseId == rhs.courseId
    }
}

struct CreateTaskRequest: Codable {
    let courseId: String?
    let title: String
    let description: String?
    let dueDate: String?
    let priority: Int?
    let estimatedHours: Double?
    let status: String?
}

struct UpdateTaskRequest: Codable {
    let title: String?
    let description: String?
    let dueDate: String?
    let priority: Int?
    let estimatedHours: Double?
    let status: String?
    let courseId: String?
}

// MARK: - Schedule

struct ScheduleBlock: Codable, Identifiable {
    let id: String
    var taskId: String?
    var date: String
    var startTime: String
    var endTime: String
    var isLocked: Bool
    var label: String?
    var task: TaskRef?

    struct TaskRef: Codable {
        let id: String
        let title: String
        let priority: Int?
        let course: CourseRef?

        struct CourseRef: Codable {
            let id: String
            let name: String
            let color: String
        }
    }
}

struct CreateBlockRequest: Codable {
    let taskId: String?
    let date: String
    let startTime: String
    let endTime: String
    let isLocked: Bool?
    let label: String?
}

struct GenerateScheduleResponse: Codable {
    let blocksCreated: Int
    let blocksRemoved: Int
    let blocks: [ScheduleBlock]
    let warnings: [String]
}

// MARK: - Chat

struct ChatRequest: Codable {
    let message: String
    let sessionId: String?
}

struct ChatResponse: Codable {
    let sessionId: String
    let response: String
    let action: ChatAction?
    let scheduleGenerated: Bool?

    struct ChatAction: Codable {
        let type: String
        let data: AnyCodable?
    }
}

// MARK: - File

struct FileUploadResponse: Codable, Identifiable {
    let id: String
    let originalName: String
    let mimeType: String
    let fileSize: Int
    let parseStatus: String
    let parsedAt: String?
    let courseId: String?
    let createdAt: String?
}

struct ExtractTasksResponse: Codable {
    let extractedCount: Int
    let tasks: [TaskItem]
    let documentType: String?
}

// MARK: - Voice

struct TranscribeResponse: Codable {
    let text: String
}

struct VoiceChatResponse: Codable {
    let transcription: String
    let sessionId: String
    let response: String
}

// MARK: - Utility

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
