import SwiftUI

struct TaskListView: View {
    @Environment(TaskStore.self) private var taskStore
    @State private var showCreateSheet = false
    @State private var sortBy = "dueDate"
    @State private var filterCourseId: String?
    @State private var showCompleted = false

    var body: some View {
        NavigationStack {
            Group {
                if taskStore.tasks.isEmpty && !taskStore.isLoading {
                    ContentUnavailableView {
                        Label("No Tasks", systemImage: "checklist")
                    } description: {
                        Text("Add tasks manually or upload a syllabus")
                    } actions: {
                        Button("Add Task") { showCreateSheet = true }
                            .buttonStyle(.bordered)
                    }
                } else {
                    List {
                        ForEach(groupedTasks, id: \.0) { courseName, tasks in
                            Section(courseName) {
                                ForEach(tasks) { task in
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
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Tasks")
            .navigationDestination(for: TaskItem.self) { task in
                TaskDetailView(task: task)
            }
            .toolbar {
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
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                TaskCreateView()
            }
            .refreshable {
                await taskStore.fetchTasks(sortBy: sortBy)
            }
            .onChange(of: sortBy) {
                Task { await taskStore.fetchTasks(sortBy: sortBy) }
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
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateFormat = "MMM d"
        return display.string(from: date)
    }

    private func isDueSoon(_ dateStr: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateStr) else { return false }
        return date.timeIntervalSinceNow < 3 * 24 * 60 * 60 && date.timeIntervalSinceNow > 0
    }
}

struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        Text("P\(priority)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(priorityColor.opacity(0.15))
            }
            .foregroundStyle(priorityColor)
    }

    private var priorityColor: Color {
        switch priority {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .green
        default: return .gray
        }
    }
}
