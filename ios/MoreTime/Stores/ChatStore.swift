import Foundation

struct ChatBubble: Identifiable {
    let id = UUID()
    let role: String // "user" or "assistant"
    let content: String
    let timestamp: Date
    /// Filenames attached with this user message (for display only).
    var attachmentNames: [String] = []
}

@Observable
final class ChatStore {
    var messages: [ChatBubble] = []
    var sessionId: String?
    var isLoading = false
    var error: String?
    var lastActionType: String?
    var didGenerateSchedule = false

    /// Files queued for the next send (uploaded; may still be parsing).
    var pendingAttachmentFiles: [FileUploadResponse] = []
    var isPreparingAttachments = false

    private let api = APIClient.shared
    private let log = ErrorLogger.shared
    private let maxMessages = 200

    /// Adds files from URLs (upload + poll until parsed or failed).
    func addAttachments(from urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isPreparingAttachments = true
        error = nil
        defer { isPreparingAttachments = false }

        struct FilePayload {
            let data: Data
            let fileName: String
            let mimeType: String
        }

        var payloads: [FilePayload] = []
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) {
                payloads.append(FilePayload(data: data, fileName: url.lastPathComponent, mimeType: Self.mimeType(for: url)))
            }
        }

        await withTaskGroup(of: Result<[FileUploadResponse], Error>.self) { group in
            for payload in payloads {
                group.addTask {
                    do {
                        let files: [FileUploadResponse] = try await self.api.upload(
                            path: "/files/upload",
                            fileData: payload.data,
                            fileName: payload.fileName,
                            mimeType: payload.mimeType,
                            fieldName: "files",
                            additionalFields: [:]
                        )
                        return .success(files)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let files):
                    pendingAttachmentFiles.append(contentsOf: files)
                case .failure(let err):
                    self.error = err.localizedDescription
                }
            }
        }

        await pollPendingParseStatus()
    }

    func removePendingAttachment(id: String) {
        pendingAttachmentFiles.removeAll { $0.id == id }
    }

    private func pollPendingParseStatus() async {
        for _ in 0 ..< 30 {
            try? await Task.sleep(for: .seconds(2))

            let pending = pendingAttachmentFiles.enumerated().filter {
                $0.element.parseStatus == "pending" || $0.element.parseStatus == "parsing"
            }
            guard !pending.isEmpty else { break }

            let updates: [(Int, FileUploadResponse)] = await withTaskGroup(of: (Int, FileUploadResponse?).self) { group in
                for (i, file) in pending {
                    group.addTask {
                        let updated: FileUploadResponse? = try? await self.api.request("GET", path: "/files/\(file.id)")
                        return (i, updated)
                    }
                }
                var results: [(Int, FileUploadResponse)] = []
                for await (i, updated) in group {
                    if let updated { results.append((i, updated)) }
                }
                return results
            }

            for (i, updated) in updates {
                if i < pendingAttachmentFiles.count {
                    pendingAttachmentFiles[i] = updated
                }
            }

            if pendingAttachmentFiles.allSatisfy({ $0.parseStatus != "pending" && $0.parseStatus != "parsing" }) {
                break
            }
        }
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "txt": return "text/plain"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
        }
    }

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let completedIds = pendingAttachmentFiles.filter { $0.parseStatus == "completed" }.map(\.id)
        let hasFailed = pendingAttachmentFiles.contains { $0.parseStatus == "failed" }
        let stillParsing = pendingAttachmentFiles.contains { $0.parseStatus == "pending" || $0.parseStatus == "parsing" }

        guard !trimmed.isEmpty || !completedIds.isEmpty else { return }
        if stillParsing {
            self.error = "Wait for attachments to finish processing."
            return
        }
        if hasFailed {
            self.error = "Remove failed attachments or try uploading again."
            return
        }

        let names = pendingAttachmentFiles.filter { $0.parseStatus == "completed" }.map(\.originalName)
        let displayContent = trimmed.isEmpty ? (names.isEmpty ? "" : " ") : trimmed
        let userBubble = ChatBubble(
            role: "user",
            content: displayContent,
            timestamp: Date(),
            attachmentNames: names
        )
        messages.append(userBubble)

        isLoading = true
        error = nil
        lastActionType = nil
        didGenerateSchedule = false
        defer { isLoading = false }

        do {
            let body = ChatRequest(
                message: trimmed,
                sessionId: sessionId,
                fileIds: completedIds.isEmpty ? nil : completedIds
            )
            let response: ChatResponse = try await api.request("POST", path: "/chat/message", body: body)

            sessionId = response.sessionId
            lastActionType = response.action?.type
            didGenerateSchedule = response.scheduleGenerated ?? false
            pendingAttachmentFiles.removeAll()
            let assistantBubble = ChatBubble(role: "assistant", content: response.response, timestamp: Date())
            messages.append(assistantBubble)
            trimMessages()
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "ChatStore", operation: "sendMessage")
            _ = messages.popLast()
        }
    }

    func sendVoice(audioURL: URL) async {
        isLoading = true
        error = nil
        lastActionType = nil
        didGenerateSchedule = false
        defer { isLoading = false }

        do {
            let data = try await Task.detached {
                try Data(contentsOf: audioURL)
            }.value

            var fields: [String: String] = [:]
            if let sid = sessionId { fields["sessionId"] = sid }

            let response: VoiceChatResponse = try await api.upload(
                path: "/voice/chat",
                fileData: data,
                fileName: "recording.m4a",
                mimeType: "audio/m4a",
                fieldName: "audio",
                additionalFields: fields
            )

            sessionId = response.sessionId

            let userBubble = ChatBubble(role: "user", content: response.transcription, timestamp: Date())
            messages.append(userBubble)

            let assistantBubble = ChatBubble(role: "assistant", content: response.response, timestamp: Date())
            messages.append(assistantBubble)
            trimMessages()
        } catch {
            self.error = error.localizedDescription
            log.log(error, source: "ChatStore", operation: "sendVoice")
        }
    }

    func clearSession() {
        messages.removeAll()
        sessionId = nil
        pendingAttachmentFiles.removeAll()
    }

    private func trimMessages() {
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }
}
