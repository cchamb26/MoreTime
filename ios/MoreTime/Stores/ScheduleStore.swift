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

    /// Last successful `fetchBlocks` range; used to refresh after task/course changes.
    private var lastFetchedStart: Date?
    private var lastFetchedEnd: Date?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Same window as initial load in `MainTabView` (month start → +3 months).
    static func defaultFetchWindow(reference: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: reference))!
        let end = calendar.date(byAdding: .month, value: 3, to: start)!
        return (start, end)
    }

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
            lastFetchedStart = startDate
            lastFetchedEnd = endDate
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "ScheduleStore", operation: "fetchBlocks")
        }
    }

    func refetchLoadedRange() async {
        if let start = lastFetchedStart, let end = lastFetchedEnd {
            await fetchBlocks(startDate: start, endDate: end)
        } else {
            let window = Self.defaultFetchWindow()
            await fetchBlocks(startDate: window.start, endDate: window.end)
        }
    }

    func generateSchedule() async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }

        do {
            let result: GenerateScheduleResponse = try await api.request("POST", path: "/schedule/generate")
            lastGenerateResult = result

            let window = Self.defaultFetchWindow()
            await fetchBlocks(startDate: window.start, endDate: window.end)
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

    func updateBlock(id: String, _ request: UpdateBlockRequest) async -> ScheduleBlock? {
        do {
            let block: ScheduleBlock = try await api.request("PATCH", path: "/schedule/\(id)", body: request)
            if let idx = blocks.firstIndex(where: { $0.id == id }) {
                blocks[idx] = block
            } else {
                blocks.append(block)
            }
            return block
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "ScheduleStore", operation: "updateBlock")
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

    /// Clears all **non-locked** schedule blocks on the server for this user, then refetches.
    /// Always calls the API (do not skip when local `blocks` looks empty — list can be stale or month-scoped).
    func clearAllBlocks() async -> Int {
        struct ClearResponse: Decodable {
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

        // Immediate UI feedback; refetch syncs with server (restores rows if delete failed).
        blocks.removeAll { !$0.isLocked }

        do {
            let result: ClearResponse = try await api.request("DELETE", path: "/schedule/clear")
            await refetchLoadedRange()
            return result.removed
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "ScheduleStore", operation: "clearAllBlocks")
            await refetchLoadedRange()
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
