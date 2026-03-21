import Foundation

@Observable
final class AuthStore {
    var currentUser: UserProfile?
    var isAuthenticated = false
    var isLoading = false
    var error: String?

    private let api = APIClient.shared

    init() {
        isAuthenticated = api.isAuthenticated
        if isAuthenticated {
            Task { await fetchProfile() }
        }
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
}
