import Foundation

@Observable
final class TaskStore {
    var tasks: [TaskItem] = []
    var courses: [Course] = []
    var isLoading = false
    var error: String?

    private let api = APIClient.shared
    private let log = ErrorLogger.shared

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
            return course
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "TaskStore", operation: "createCourse")
            return nil
        }
    }

    func deleteCourse(id: String) async -> Bool {
        do {
            try await api.request("DELETE", path: "/courses/\(id)") as Void
            courses.removeAll { $0.id == id }
            return true
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "TaskStore", operation: "deleteCourse")
            return false
        }
    }
}
