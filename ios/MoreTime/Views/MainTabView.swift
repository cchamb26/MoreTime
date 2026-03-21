import SwiftUI

struct MainTabView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Calendar", systemImage: "calendar", value: 0) {
                CalendarView()
            }

            Tab("Tasks", systemImage: "checklist", value: 1) {
                TaskListView()
            }

            Tab("Chat", systemImage: "message", value: 2) {
                ChatView()
            }

            Tab("Settings", systemImage: "gear", value: 3) {
                SettingsView()
            }
        }
        .tint(.primary)
        .task {
            await taskStore.fetchTasks()
            await taskStore.fetchCourses()

            let now = Date()
            let calendar = Calendar.current
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            await scheduleStore.fetchBlocks(startDate: start, endDate: end)
        }
    }
}
