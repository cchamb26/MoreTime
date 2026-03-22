import SwiftUI

struct MainTabView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(0)

            TaskListView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(1)

            ChatView()
                .tabItem { Label("Chat", systemImage: "message") }
                .tag(2)

            SemesterHeatMapView()
                .tabItem { Label("Semester", systemImage: "chart.bar.xaxis") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(4)
        }
        .tint(.primary)
        .task {
            taskStore.onDidMutateTasksOrCourses = { await scheduleStore.refetchLoadedRange() }

            let window = ScheduleStore.defaultFetchWindow()
            async let fetchTasks: Void = taskStore.fetchTasks()
            async let fetchCourses: Void = taskStore.fetchCourses()
            async let fetchBlocks: Void = scheduleStore.fetchBlocks(startDate: window.start, endDate: window.end)
            _ = await (fetchTasks, fetchCourses, fetchBlocks)
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 0 {
                Task {
                    async let refreshBlocks: Void = scheduleStore.refetchLoadedRange()
                    async let refreshTasks: Void = taskStore.fetchTasks()
                    _ = await (refreshBlocks, refreshTasks)
                }
            }
        }
    }
}
