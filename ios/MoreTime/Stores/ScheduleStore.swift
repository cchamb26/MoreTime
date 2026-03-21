import Foundation

@Observable
final class ScheduleStore {
    var blocks: [ScheduleBlock] = []
    var isLoading = false
    var isGenerating = false
    var error: String?
    var lastGenerateResult: GenerateScheduleResponse?

    private let api = APIClient.shared
    private let log = ErrorLogger.shared

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func fetchBlocks(startDate: Date, endDate: Date) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let query = [
                "startDate": dateFormatter.string(from: startDate),
                "endDate": dateFormatter.string(from: endDate),
            ]
            blocks = try await api.request("GET", path: "/schedule", query: query)
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "ScheduleStore", operation: "fetchBlocks")
        }
    }

    func generateSchedule() async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }

        do {
            let result: GenerateScheduleResponse = try await api.request("POST", path: "/schedule/generate")
            lastGenerateResult = result

            let now = Date()
            let calendar = Calendar.current
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            await fetchBlocks(startDate: start, endDate: end)
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "ScheduleStore", operation: "generateSchedule")
        }
    }

    func createBlock(_ request: CreateBlockRequest) async -> ScheduleBlock? {
        do {
            let block: ScheduleBlock = try await api.request("POST", path: "/schedule", body: request)
            blocks.append(block)
            return block
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "ScheduleStore", operation: "createBlock")
            return nil
        }
    }

    func deleteBlock(id: String) async -> Bool {
        do {
            try await api.request("DELETE", path: "/schedule/\(id)") as Void
            blocks.removeAll { $0.id == id }
            return true
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "ScheduleStore", operation: "deleteBlock")
            return false
        }
    }

    func clearAllBlocks() async -> Int {
        do {
            struct ClearResponse: Decodable { let removed: Int }
            let result: ClearResponse = try await api.request("DELETE", path: "/schedule/clear")
            blocks.removeAll { !$0.isLocked }
            return result.removed
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "ScheduleStore", operation: "clearAllBlocks")
            return 0
        }
    }

    // MARK: - Helpers

    func blocksForDate(_ date: Date) -> [ScheduleBlock] {
        let dateStr = dateFormatter.string(from: date)
        return blocks
            .filter { $0.date.hasPrefix(dateStr) }
            .sorted { $0.startTime < $1.startTime }
    }
}
