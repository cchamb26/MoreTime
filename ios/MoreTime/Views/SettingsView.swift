import SwiftUI

struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var preferredStartTime = "09:00"
    @State private var preferredEndTime = "22:00"
    @State private var maxHoursPerDay = 8.0
    @State private var breakDuration = 15.0
    @State private var showCourseManagement = false
    @State private var showFileUpload = false
    @State private var showLockedBlocks = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let user = authStore.currentUser {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Timezone", value: user.timezone ?? "Not set")
                    }
                }

                Section("Study Preferences") {
                    HStack {
                        Text("Start Time")
                        Spacer()
                        Text(preferredStartTime)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("End Time")
                        Spacer()
                        Text(preferredEndTime)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading) {
                        Text("Max Hours/Day: \(maxHoursPerDay, specifier: "%.0f")")
                        Slider(value: $maxHoursPerDay, in: 2...16, step: 1)
                    }

                    VStack(alignment: .leading) {
                        Text("Break Duration: \(breakDuration, specifier: "%.0f") min")
                        Slider(value: $breakDuration, in: 5...60, step: 5)
                    }
                }

                Section("Manage") {
                    Button {
                        showCourseManagement = true
                    } label: {
                        Label("Courses", systemImage: "paintpalette")
                    }

                    Button {
                        showLockedBlocks = true
                    } label: {
                        Label("Class Schedule (Locked Blocks)", systemImage: "lock")
                    }

                    Button {
                        showFileUpload = true
                    } label: {
                        Label("Upload Syllabus", systemImage: "doc.badge.plus")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await authStore.logout() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showCourseManagement) {
                CourseManagementView()
            }
            .sheet(isPresented: $showFileUpload) {
                FileUploadView(courseId: nil)
            }
            .sheet(isPresented: $showLockedBlocks) {
                LockedBlocksView()
            }
        }
    }
}

struct LockedBlocksView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var selectedDay = 1 // Monday
    @State private var startTime = "09:00"
    @State private var endTime = "10:00"

    private let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Add Recurring Block") {
                    TextField("Label (e.g., CS310 Lecture)", text: $label)

                    Picker("Day", selection: $selectedDay) {
                        ForEach(0..<7) { i in
                            Text(days[i]).tag(i)
                        }
                    }

                    HStack {
                        Text("Time")
                        Spacer()
                        Text("\(startTime) - \(endTime)")
                            .foregroundStyle(.secondary)
                    }

                    Button("Add Block") {
                        addLockedBlock()
                    }
                    .disabled(label.isEmpty)
                }

                Section("Current Locked Blocks") {
                    let locked = scheduleStore.blocks.filter(\.isLocked)
                    if locked.isEmpty {
                        Text("No locked blocks")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(locked) { block in
                            HStack {
                                Text(block.label ?? "Block")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(block.startTime)-\(block.endTime)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Class Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addLockedBlock() {
        let calendar = Calendar.current
        let today = Date()

        // Find next occurrence of selected day
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        components.weekday = selectedDay + 1
        guard let targetDate = calendar.date(from: components) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        Task {
            let request = CreateBlockRequest(
                taskId: nil,
                date: formatter.string(from: targetDate),
                startTime: startTime,
                endTime: endTime,
                isLocked: true,
                label: label
            )
            if await scheduleStore.createBlock(request) != nil {
                label = ""
            }
        }
    }
}
