import SwiftUI
import SwiftData

@main
struct MoreTimeApp: App {
    @State private var authStore = AuthStore()
    @State private var taskStore = TaskStore()
    @State private var scheduleStore = ScheduleStore()
    @State private var chatStore = ChatStore()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CachedTask.self,
            CachedScheduleBlock.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authStore)
                .environment(taskStore)
                .environment(scheduleStore)
                .environment(chatStore)
        }
        .modelContainer(sharedModelContainer)
    }
}
