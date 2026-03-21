import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var authStore

    var body: some View {
        Group {
            if authStore.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: authStore.isAuthenticated)
    }
}
