import SwiftUI

struct CourseManagementView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(\.dismiss) private var dismiss

    @State private var newCourseName = ""
    @State private var newCourseColor = "#6B7280"
    @State private var showColorPicker = false

    private let presetColors = [
        "#EF4444", "#F97316", "#EAB308", "#22C55E",
        "#06B6D4", "#3B82F6", "#8B5CF6", "#EC4899",
        "#6B7280", "#78716C",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Add Course") {
                    TextField("Course Name", text: $newCourseName)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color")
                            .font(.subheadline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                            ForEach(presetColors, id: \.self) { color in
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if color == newCourseColor {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .onTapGesture {
                                        newCourseColor = color
                                    }
                            }
                        }
                    }

                    Button("Add Course") {
                        Task {
                            _ = await taskStore.createCourse(name: newCourseName, color: newCourseColor)
                            newCourseName = ""
                        }
                    }
                    .disabled(newCourseName.isEmpty)
                }

                Section("Your Courses") {
                    if taskStore.courses.isEmpty {
                        Text("No courses yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(taskStore.courses) { course in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: course.color))
                                    .frame(width: 12, height: 12)

                                Text(course.name)
                                    .font(.subheadline)

                                Spacer()

                                if let count = course._count?.tasks {
                                    Text("\(count) tasks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let course = taskStore.courses[index]
                                Task { await taskStore.deleteCourse(id: course.id) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Courses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await taskStore.fetchCourses()
            }
        }
    }
}
