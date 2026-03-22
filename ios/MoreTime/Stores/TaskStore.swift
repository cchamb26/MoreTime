import Foundation

@Observable
final class TaskStore {
    var tasks: [TaskItem] = []
    var courses: [Course] = []
    var isLoading = false
    var error: String?

    /// Set from the app shell (e.g. `MainTabView`) to refresh calendar blocks after task/course changes.
    var onDidMutateTasksOrCourses: (() async -> Void)?

    private let api = APIClient.shared
    private let log = ErrorLogger.shared

    private func invokeScheduleRefreshCallback() async {
        await onDidMutateTasksOrCourses?()
    }

    /// Call after server-backed task changes that did not go through `createTask` / `updateTask` / etc. (e.g. file extract).
    func notifyScheduleRefresh() async {
        await invokeScheduleRefreshCallback()
    }

    // MARK: - Tasks

    func fetchTasks(courseId: String? = nil, status: String? = nil, sortBy: String = "dueDate") async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            var query: [String: String] = ["sortBy": sortBy]
            if let courseId { query["courseId"] = courseId }
            if let status { query["status"] = status }

            tasks = try await api.request("GET", path: "/tasks", query: query)
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "TaskStore", operation: "fetchTasks")
        }
    }

    func createTask(_ request: CreateTaskRequest) async -> TaskItem? {
        do {
            let task: TaskItem = try await api.request("POST", path: "/tasks", body: request)
            tasks.insert(task, at: 0)
            await invokeScheduleRefreshCallback()
            return task
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "TaskStore", operation: "createTask")
            return nil
        }
    }

    func updateTask(id: String, _ request: UpdateTaskRequest) async -> TaskItem? {
        do {
            let task: TaskItem = try await api.request("PATCH", path: "/tasks/\(id)", body: request)
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                tasks[idx] = task
            }
            await invokeScheduleRefreshCallback()
            return task
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "TaskStore", operation: "updateTask")
            return nil
        }
    }

    func deleteTask(id: String) async -> Bool {
        do {
            try await api.request("DELETE", path: "/tasks/\(id)") as Void
            tasks.removeAll { $0.id == id }
            await invokeScheduleRefreshCallback()
            return true
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "TaskStore", operation: "deleteTask")
            return false
        }
    }

    func completeTask(id: String) async {
        _ = await updateTask(id: id, UpdateTaskRequest(
            title: nil, description: nil, dueDate: nil,
            priority: nil, estimatedHours: nil, status: "completed", courseId: nil
        ))
    }

    func clearAllTasks() async -> Int {
        do {
            let result: TasksRemovedCountResponse = try await api.request("DELETE", path: "/tasks/clear")
            tasks.removeAll()
            await invokeScheduleRefreshCallback()
            return result.removed
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "TaskStore", operation: "clearAllTasks")
            return 0
        }
    }

    /// Deletes tasks whose due time falls on this **local** calendar day (same rule as the calendar “Due” section).
    func deleteTasksDueOnLocalDay(_ date: Date) async -> Int {
        error = nil
        let (startISO, endISO) = Self.isoRangeForLocalDay(date)

        do {
            let result: TasksRemovedCountResponse = try await api.request(
                "DELETE",
                path: "/tasks/due-in-day",
                query: ["start": startISO, "end": endISO]
            )
            await fetchTasks()
            await invokeScheduleRefreshCallback()
            return result.removed
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "TaskStore", operation: "deleteTasksDueOnLocalDay")
            await fetchTasks()
            return 0
        }
    }

    private static func isoRangeForLocalDay(_ date: Date, calendar: Calendar = .current) -> (start: String, end: String) {
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withTimeZone]
            f.timeZone = calendar.timeZone
            return (f.string(from: date), f.string(from: date))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        formatter.timeZone = calendar.timeZone
        return (formatter.string(from: startDate), formatter.string(from: endDate))
    }

    // MARK: - Courses

    func fetchCourses() async {
        do {
            courses = try await api.request("GET", path: "/courses")
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "TaskStore", operation: "fetchCourses")
        }
    }

    func createCourse(name: String, color: String) async -> Course? {
        do {
            let body = CreateCourseRequest(name: name, color: color, metadata: nil)
            let course: Course = try await api.request("POST", path: "/courses", body: body)
            courses.append(course)
            await invokeScheduleRefreshCallback()
            return course
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "TaskStore", operation: "createCourse")
            return nil
        }
    }

    func updateCourse(id: String, name: String?, color: String?) async -> Course? {
        do {
            let body = UpdateCourseRequest(name: name, color: color)
            let course: Course = try await api.request("PATCH", path: "/courses/\(id)", body: body)
            if let idx = courses.firstIndex(where: { $0.id == id }) {
                courses[idx] = course
            }
            await invokeScheduleRefreshCallback()
            return course
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "TaskStore", operation: "updateCourse")
            return nil
        }
    }

    func deleteCourse(id: String) async -> Bool {
        do {
            try await api.request("DELETE", path: "/courses/\(id)") as Void
            courses.removeAll { $0.id == id }
            for idx in tasks.indices where tasks[idx].courseId == id {
                tasks[idx].courseId = nil
                tasks[idx].course = nil
            }
            await invokeScheduleRefreshCallback()
            return true
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "TaskStore", operation: "deleteCourse")
            return false
        }
    }
}

// MARK: - API helpers

private struct TasksRemovedCountResponse: Decodable {
    let removed: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .removed) {
            removed = i
        } else if let d = try? c.decode(Double.self, forKey: .removed) {
            removed = Int(d)
        } else {
            removed = 0
        }
    }
    private enum CodingKeys: String, CodingKey { case removed }
}
