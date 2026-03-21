import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int, String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .unauthorized: return "Please log in again"
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .decodingError(let err): return "Data error: \(err.localizedDescription)"
        case .networkError(let err): return err.localizedDescription
        }
    }
}

@Observable
final class APIClient {
    static let shared = APIClient()

    #if DEBUG
    var baseURL = "http://localhost:3000"
    #else
    var baseURL = "https://api.moretime.app"
    #endif

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys
        return e
    }()

    private var isRefreshing = false

    private var accessToken: String? {
        get { KeychainHelper.read("accessToken") }
        set {
            if let newValue { KeychainHelper.save(newValue, for: "accessToken") }
            else { KeychainHelper.delete("accessToken") }
        }
    }

    private var refreshToken: String? {
        get { KeychainHelper.read("refreshToken") }
        set {
            if let newValue { KeychainHelper.save(newValue, for: "refreshToken") }
            else { KeychainHelper.delete("refreshToken") }
        }
    }

    var isAuthenticated: Bool {
        accessToken != nil
    }

    func setTokens(access: String, refresh: String) {
        self.accessToken = access
        self.refreshToken = refresh
    }

    func clearTokens() {
        KeychainHelper.deleteAll()
    }

    // MARK: - Generic Request

    func request<T: Decodable>(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil,
        query: [String: String]? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        var urlComponents = URLComponents(string: "\(baseURL)\(path)")!
        if let query {
            urlComponents.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = urlComponents.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 401 && authenticated {
            // Try token refresh
            if let refreshed = try? await attemptTokenRefresh() {
                self.setTokens(access: refreshed.accessToken, refresh: refreshed.refreshToken)
                return try await self.request(method, path: path, body: body, query: query, authenticated: true)
            }
            throw APIError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            let errorMsg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, errorMsg)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // Void response variant
    func request(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) async throws {
        let _: EmptyResponse = try await request(method, path: path, body: body, authenticated: authenticated)
    }

    // MARK: - Multipart Upload

    func upload<T: Decodable>(
        path: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        fieldName: String = "files",
        additionalFields: [String: String] = [:]
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        for (key, value) in additionalFields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 400 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.serverError(code, "Upload failed")
        }

        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Token Refresh

    private func attemptTokenRefresh() async throws -> TokenRefreshResponse {
        guard let token = refreshToken else { throw APIError.unauthorized }
        return try await request("POST", path: "/auth/refresh", body: ["refreshToken": token], authenticated: false)
    }
}

// MARK: - Helpers

private struct EmptyResponse: Decodable {}

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        _encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
