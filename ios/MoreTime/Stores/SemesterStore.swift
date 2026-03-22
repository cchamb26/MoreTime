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

    func reset() {
        semesterPlan = nil
        error = nil
    }
}
