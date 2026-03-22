import Foundation

@Observable
final class AuthStore {
    var currentUser: UserProfile?
    var isAuthenticated = false
    var isLoading = false
    var error: String?

    private let api = APIClient.shared

    init() {
        #if DEBUG
        // Dev bypass: skip auth so you can test everything else
        isAuthenticated = true
        currentUser = UserProfile(
            id: "00000000-0000-0000-0000-000000000000",
            email: "dev@moretime.local",
            name: "Dev User",
            timezone: "America/New_York",
            preferences: nil,
            createdAt: nil
        )
        #else
        isAuthenticated = api.isAuthenticated
        #endif
    }

    func register(email: String, name: String, password: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let body = ["email": email, "name": name, "password": password]
            let response: AuthResponse = try await api.request("POST", path: "/auth/register", body: body, authenticated: false)
            api.setTokens(access: response.accessToken, refresh: response.refreshToken)
            currentUser = response.user
            isAuthenticated = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func login(email: String, password: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let body = ["email": email, "password": password]
            let response: AuthResponse = try await api.request("POST", path: "/auth/login", body: body, authenticated: false)
            api.setTokens(access: response.accessToken, refresh: response.refreshToken)
            currentUser = response.user
            isAuthenticated = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logout() async {
        try? await api.request("POST", path: "/auth/logout") as Void
        api.clearTokens()
        currentUser = nil
        isAuthenticated = false
    }

    func fetchProfile() async {
        do {
            let user: UserProfile = try await api.request("GET", path: "/auth/me")
            currentUser = user
        } catch {
            // Token might be expired
            if case APIError.unauthorized = error {
                isAuthenticated = false
                api.clearTokens()
            }
        }
    }

    /// Merges into existing profile `preferences` and PATCHes `/auth/me` (server replaces whole JSON object).
    func updatePreferences(merging updates: [String: Any]) async -> Bool {
        var merged = Self.preferencesDictionary(from: currentUser)
        for (key, value) in updates {
            merged[key] = value
        }
        let codablePrefs = merged.mapValues { AnyCodable($0) }

        struct PatchBody: Codable {
            var preferences: [String: AnyCodable]
        }

        do {
            let user: UserProfile = try await api.request("PATCH", path: "/auth/me", body: PatchBody(preferences: codablePrefs))
            currentUser = user
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    static func preferencesDictionary(from profile: UserProfile?) -> [String: Any] {
        guard let prefs = profile?.preferences else { return [:] }
        var out: [String: Any] = [:]
        for (key, any) in prefs {
            out[key] = any.value
        }
        return out
    }
}
