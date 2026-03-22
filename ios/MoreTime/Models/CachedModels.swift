import Foundation
import SwiftData

private let sharedISOFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    return f
}()

private let sharedDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

@Model
final class CachedTask {
    @Attribute(.unique) var id: String
    var courseId: String?
    var title: String
    var taskDescription: String
    var dueDate: Date?
    var priority: Int
    var estimatedHours: Double
    var status: String
    var courseName: String?
    var courseColor: String?
    var lastSynced: Date

    init(from task: TaskItem) {
        self.id = task.id
        self.courseId = task.courseId
        self.title = task.title
        self.taskDescription = task.description ?? ""
        self.dueDate = task.dueDate.flatMap { sharedISOFormatter.date(from: $0) }
        self.priority = task.priority
        self.estimatedHours = task.estimatedHours
        self.status = task.status
        self.courseName = task.course?.name
        self.courseColor = task.course?.color
        self.lastSynced = Date()
    }
}

@Model
final class CachedScheduleBlock {
    @Attribute(.unique) var id: String
    var taskId: String?
    var date: Date
    var startTime: String
    var endTime: String
    var isLocked: Bool
    var label: String?
    var taskTitle: String?
    var courseColor: String?
    var lastSynced: Date

    init(from block: ScheduleBlock) {
        self.id = block.id
        self.taskId = block.taskId
        self.date = sharedDateFormatter.date(from: block.date) ?? Date()
        self.startTime = block.startTime
        self.endTime = block.endTime
        self.isLocked = block.isLocked
        self.label = block.label
        self.taskTitle = block.task?.title
        self.courseColor = block.classCourse?.color ?? block.task?.course?.color
        self.lastSynced = Date()
    }
}
