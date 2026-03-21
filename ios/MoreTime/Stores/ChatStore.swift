import Foundation

struct ChatBubble: Identifiable {
    let id = UUID()
    let role: String // "user" or "assistant"
    let content: String
    let timestamp: Date
}

@Observable
final class ChatStore {
    var messages: [ChatBubble] = []
    var sessionId: String?
    var isLoading = false
    var error: String?

    private let api = APIClient.shared

    func sendMessage(_ text: String) async {
        let userBubble = ChatBubble(role: "user", content: text, timestamp: Date())
        messages.append(userBubble)

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let body = ChatRequest(message: text, sessionId: sessionId)
            let response: ChatResponse = try await api.request("POST", path: "/chat/message", body: body)

            sessionId = response.sessionId
            let assistantBubble = ChatBubble(role: "assistant", content: response.response, timestamp: Date())
            messages.append(assistantBubble)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func sendVoice(audioURL: URL) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let data = try Data(contentsOf: audioURL)
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
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clearSession() {
        messages.removeAll()
        sessionId = nil
    }
}
