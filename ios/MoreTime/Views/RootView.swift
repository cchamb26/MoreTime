import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var authStore
    private let errorLogger = ErrorLogger.shared

    var body: some View {
        Group {
            if authStore.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: authStore.isAuthenticated)
        .task {
            if authStore.isAuthenticated {
                await authStore.fetchProfile()
            }
        }
        .errorBanner(errorLogger.currentError) {
            errorLogger.dismissCurrent()
        }
    }
}
