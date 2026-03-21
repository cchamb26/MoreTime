import SwiftUI

struct TaskDetailView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem
    @State private var title: String
    @State private var description: String
    @State private var dueDate: Date
    @State private var hasDueDate: Bool
    @State private var priority: Int
    @State private var estimatedHours: Double
    @State private var status: String
    @State private var selectedCourseId: String?
    @State private var isSaving = false

    init(task: TaskItem) {
        self.task = task
        _title = State(initialValue: task.title)
        _description = State(initialValue: task.description ?? "")
        let formatter = ISO8601DateFormatter()
        let date = task.dueDate.flatMap { formatter.date(from: $0) }
        _dueDate = State(initialValue: date ?? Date())
        _hasDueDate = State(initialValue: date != nil)
        _priority = State(initialValue: task.priority)
        _estimatedHours = State(initialValue: task.estimatedHours)
        _status = State(initialValue: task.status)
        _selectedCourseId = State(initialValue: task.courseId)
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $title)

                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(3...6)

                Picker("Course", selection: $selectedCourseId) {
                    Text("None").tag(nil as String?)
                    ForEach(taskStore.courses) { course in
                        HStack {
                            Circle()
                                .fill(Color(hex: course.color))
                                .frame(width: 8, height: 8)
                            Text(course.name)
                        }
                        .tag(course.id as String?)
                    }
                }
            }

            Section("Schedule") {
                Toggle("Due Date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }

                VStack(alignment: .leading) {
                    Text("Estimated Hours: \(estimatedHours, specifier: "%.1f")")
                        .font(.subheadline)
                    Slider(value: $estimatedHours, in: 0.5...50, step: 0.5)
                }

                Picker("Priority", selection: $priority) {
                    Text("Highest").tag(1)
                    Text("High").tag(2)
                    Text("Medium").tag(3)
                    Text("Low").tag(4)
                    Text("Lowest").tag(5)
                }
            }

            Section("Status") {
                Picker("Status", selection: $status) {
                    Text("Pending").tag("pending")
                    Text("In Progress").tag("in_progress")
                    Text("Completed").tag("completed")
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Edit Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(title.isEmpty || isSaving)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let formatter = ISO8601DateFormatter()
        let dueDateStr = hasDueDate ? formatter.string(from: dueDate) : nil

        let request = UpdateTaskRequest(
            title: title,
            description: description,
            dueDate: dueDateStr,
            priority: priority,
            estimatedHours: estimatedHours,
            status: status,
            courseId: selectedCourseId
        )

        if await taskStore.updateTask(id: task.id, request) != nil {
            dismiss()
        }
    }
}

struct TaskCreateView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var dueDate = Date().addingTimeInterval(7 * 24 * 60 * 60)
    @State private var hasDueDate = true
    @State private var priority = 2
    @State private var estimatedHours = 2.0
    @State private var selectedCourseId: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)

                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)

                    Picker("Course", selection: $selectedCourseId) {
                        Text("None").tag(nil as String?)
                        ForEach(taskStore.courses) { course in
                            HStack {
                                Circle()
                                    .fill(Color(hex: course.color))
                                    .frame(width: 8, height: 8)
                                Text(course.name)
                            }
                            .tag(course.id as String?)
                        }
                    }
                }

                Section("Schedule") {
                    Toggle("Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }

                    VStack(alignment: .leading) {
                        Text("Estimated Hours: \(estimatedHours, specifier: "%.1f")")
                            .font(.subheadline)
                        Slider(value: $estimatedHours, in: 0.5...50, step: 0.5)
                    }

                    Picker("Priority", selection: $priority) {
                        Text("Highest").tag(1)
                        Text("High").tag(2)
                        Text("Medium").tag(3)
                        Text("Low").tag(4)
                        Text("Lowest").tag(5)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await create() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Add") }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }

        let formatter = ISO8601DateFormatter()
        let request = CreateTaskRequest(
            courseId: selectedCourseId,
            title: title,
            description: description.isEmpty ? nil : description,
            dueDate: hasDueDate ? formatter.string(from: dueDate) : nil,
            priority: priority,
            estimatedHours: estimatedHours,
            status: nil
        )

        if await taskStore.createTask(request) != nil {
            dismiss()
        }
    }
}
