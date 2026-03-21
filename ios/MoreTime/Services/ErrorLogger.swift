import Foundation
import OSLog

struct AppLogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let source: String
    let operation: String
    let message: String
    let level: Level

    enum Level: String {
        case error, warning, info
    }
}

private let logger = Logger(subsystem: "com.moretime.app", category: "API")

@Observable
final class ErrorLogger {
    static let shared = ErrorLogger()

    /// Most recent error for the toast banner
    var currentError: AppLogEntry?

    /// Rolling log kept in memory for the debug console
    private(set) var entries: [AppLogEntry] = []
    private let maxEntries = 100

    func log(_ error: Error, source: String, operation: String) {
        let entry = classify(error, source: source, operation: operation)
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst() }

        // OS log for Xcode console / Console.app
        logger.error("[\(source)] \(operation): \(entry.message)")

        // Surface to UI
        currentError = entry

        // Auto-dismiss after 4 seconds
        let id = entry.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if currentError?.id == id { currentError = nil }
        }
    }

    func dismissCurrent() {
        currentError = nil
    }

    func clearLog() {
        entries.removeAll()
    }

    // MARK: - Classify errors into human-readable messages

    private func classify(_ error: Error, source: String, operation: String) -> AppLogEntry {
        let message: String
        let level: AppLogEntry.Level

        switch error {
        case let apiErr as APIError:
            switch apiErr {
            case .networkError(let inner):
                let nsError = inner as NSError
                if nsError.code == NSURLErrorNotConnectedToInternet {
                    message = "No internet connection"
                    level = .warning
                } else if nsError.code == NSURLErrorTimedOut {
                    message = "Request timed out — server may be down"
                    level = .error
                } else if nsError.code == NSURLErrorCannotConnectToHost
                            || nsError.code == NSURLErrorCannotFindHost {
                    message = "Cannot reach server at \(APIClient.shared.baseURL)"
                    level = .error
                } else if nsError.domain == NSURLErrorDomain {
                    message = "Network error: \(nsError.localizedDescription)"
                    level = .error
                } else {
                    message = "Network error: \(inner.localizedDescription)"
                    level = .error
                }
            case .unauthorized:
                message = "Session expired — please log in again"
                level = .warning
            case .serverError(let code, let msg):
                message = "Server \(code): \(msg)"
                level = .error
            case .decodingError(let inner):
                message = "Failed to parse response: \(inner.localizedDescription)"
                level = .error
            case .invalidURL:
                message = "Invalid request URL"
                level = .error
            }
        case let urlError as URLError:
            message = "Connection failed: \(urlError.localizedDescription) (code \(urlError.code.rawValue))"
            level = .error
        default:
            message = error.localizedDescription
            level = .error
        }

        return AppLogEntry(source: source, operation: operation, message: message, level: level)
    }
}
