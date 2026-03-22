import Foundation

@Observable
final class SemesterStore {
    var semesterPlan: SemesterPlan?
    var uploadedFiles: [FileUploadResponse] = []
    var isLoading = false
    var isUploading = false
    var error: String?

    private let api = APIClient.shared
    private let log = ErrorLogger.shared

    func generatePlan(fileIds: [String], start: String, end: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let body = SemesterPlanRequest(fileIds: fileIds, semesterStart: start, semesterEnd: end)
            let plan: SemesterPlan = try await api.request("POST", path: "/files/semester-plan", body: body)
            semesterPlan = plan
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "SemesterStore", operation: "generatePlan")
        }
    }

    func fetchUploadedFiles() async {
        do {
            let files: [FileUploadResponse] = try await api.request("GET", path: "/files")
            uploadedFiles = files.filter { $0.parseStatus == "completed" }
        } catch {
            log.log(error, source: "SemesterStore", operation: "fetchFiles")
        }
    }

    func uploadFiles(payloads: [(data: Data, fileName: String, mimeType: String)]) async -> [FileUploadResponse] {
        isUploading = true
        defer { isUploading = false }

        var results: [FileUploadResponse] = []
        for payload in payloads {
            do {
                let files: [FileUploadResponse] = try await api.upload(
                    path: "/files/upload",
                    fileData: payload.data,
                    fileName: payload.fileName,
                    mimeType: payload.mimeType
                )
                results.append(contentsOf: files)
            } catch {
                log.log(error, source: "SemesterStore", operation: "uploadFile")
            }
        }
        return results
    }

    var isApplying = false
    var appliedCount = 0

    func applyToCalendar() async -> Int {
        guard let plan = semesterPlan else { return 0 }
        isApplying = true
        error = nil
        defer { isApplying = false }

        let allEvents = plan.weeks.flatMap(\.events)
        var created = 0

        for event in allEvents {
            let dueDate = "\(event.dueDate)T23:59:00Z"
            let request = CreateTaskRequest(
                courseId: nil,
                title: event.title,
                description: "\(event.courseName) — \(event.type.capitalized)",
                dueDate: dueDate,
                priority: priorityForType(event.type),
                estimatedHours: event.estimatedHours,
                status: nil
            )
            do {
                let _: TaskItem = try await api.request("POST", path: "/tasks", body: request)
                created += 1
            } catch {
                log.log(error, source: "SemesterStore", operation: "applyEvent")
            }
        }

        appliedCount = created
        return created
    }

    private func priorityForType(_ type: String) -> Int {
        switch type.lowercased() {
        case "exam": return 1
        case "project", "paper": return 2
        default: return 3
        }
    }

    func reset() {
        semesterPlan = nil
        error = nil
        appliedCount = 0
    }
}
