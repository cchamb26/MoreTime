import SwiftUI

struct TaskListView: View {
    @Environment(TaskStore.self) private var taskStore
    @State private var showCreateSheet = false
    @State private var sortBy = "dueDate"
    @State private var filterCourseId: String?
    @State private var showCompleted = false
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if taskStore.tasks.isEmpty && !taskStore.isLoading {
                    emptyStateView
                } else {
                    taskListContent
                }
            }
            .navigationTitle("Tasks")
            .navigationDestination(for: TaskItem.self) { task in
                TaskDetailView(task: task)
            }
            .toolbar { toolbarItems }
            .sheet(isPresented: $showCreateSheet) {
                TaskCreateView()
            }
            .alert("Clear All Tasks", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    Task { await taskStore.clearAllTasks() }
                }
            } message: {
                Text("This will permanently delete all your tasks and any associated schedule blocks. This cannot be undone.")
            }
            .refreshable {
                await taskStore.fetchTasks(sortBy: sortBy)
            }
            .onChange(of: sortBy) {
                Task { await taskStore.fetchTasks(sortBy: sortBy) }
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Tasks", systemImage: "checklist")
        } description: {
            Text("Add tasks manually or upload a syllabus")
        } actions: {
            Button("Add Task") { showCreateSheet = true }
                .buttonStyle(.bordered)
        }
    }

    private var taskListContent: some View {
        List {
            ForEach(groupedTasks, id: \.0) { courseName, tasks in
                Section(courseName) {
                    ForEach(tasks) { task in
                        taskRow(for: task)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func taskRow(for task: TaskItem) -> some View {
        NavigationLink(value: task) {
            TaskRow(task: task)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await taskStore.deleteTask(id: task.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            if task.status != "completed" {
                Button {
                    Task { await taskStore.completeTask(id: task.id) }
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Picker("Sort", selection: $sortBy) {
                    Text("Due Date").tag("dueDate")
                    Text("Priority").tag("priority")
                    Text("Created").tag("createdAt")
                }
                Toggle("Show Completed", isOn: $showCompleted)
                Divider()
                Button("Clear All Tasks", role: .destructive) {
                    showClearConfirm = true
                }
                .disabled(taskStore.tasks.isEmpty)
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
    }

    private var groupedTasks: [(String, [TaskItem])] {
        let filtered = taskStore.tasks.filter { showCompleted || $0.status != "completed" }
        let grouped = Dictionary(grouping: filtered) { $0.course?.name ?? "General" }
        return grouped.sorted { $0.key < $1.key }
    }
}

struct TaskRow: View {
    let task: TaskItem

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: task.course?.color ?? "#6B7280"))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(task.status == "completed")
                    .foregroundStyle(task.status == "completed" ? .secondary : .primary)

                HStack(spacing: 8) {
                    if let dueDate = task.dueDate {
                        Label(formatDueDate(dueDate), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(isDueSoon(dueDate) ? .red : .secondary)
                    }

                    Label("\(task.estimatedHours, specifier: "%.1f")h", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            PriorityBadge(priority: task.priority)
        }
        .padding(.vertical, 2)
    }

    private func formatDueDate(_ dateStr: String) -> String {
        guard let date = Self.isoFormatter.date(from: dateStr) else { return dateStr }
        return Self.displayFormatter.string(from: date)
    }

    private func isDueSoon(_ dateStr: String) -> Bool {
        guard let date = Self.isoFormatter.date(from: dateStr) else { return false }
        return date.timeIntervalSinceNow < 3 * 24 * 60 * 60 && date.timeIntervalSinceNow > 0
    }
}

struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        Text(TaskPriorityUI.label(for: priority))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(TaskPriorityUI.color(for: priority).opacity(0.15))
            }
            .foregroundStyle(TaskPriorityUI.color(for: priority))
    }
}
