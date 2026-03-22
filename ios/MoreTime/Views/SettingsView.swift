import SwiftUI

struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var studyStart = SettingsView.defaultTime(hour: 9, minute: 0)
    @State private var studyEnd = SettingsView.defaultTime(hour: 22, minute: 0)
    @State private var maxHoursPerDay = 8.0
    @State private var breakDuration = 15.0
    @State private var prefsSaveMessage: String?
    @State private var showClassSchedule = false
    @State private var showFileUpload = false
    @State private var showDebugLog = false

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
                    DatePicker("Preferred start", selection: $studyStart, displayedComponents: .hourAndMinute)
                    DatePicker("Preferred end", selection: $studyEnd, displayedComponents: .hourAndMinute)

                    VStack(alignment: .leading) {
                        Text("Max hours per day: \(maxHoursPerDay, specifier: "%.0f")")
                        Slider(value: $maxHoursPerDay, in: 2...16, step: 1)
                    }

                    VStack(alignment: .leading) {
                        Text("Break duration: \(breakDuration, specifier: "%.0f") min")
                        Slider(value: $breakDuration, in: 5...60, step: 5)
                    }

                    Button("Save study preferences") {
                        Task {
                            let ok = await authStore.updatePreferences(merging: [
                                "preferredStartTime": Self.hhmm(from: studyStart),
                                "preferredEndTime": Self.hhmm(from: studyEnd),
                                "maxHoursPerDay": Int(maxHoursPerDay),
                                "breakDuration": Int(breakDuration),
                            ])
                            prefsSaveMessage = ok ? "Saved." : (authStore.error ?? "Could not save.")
                        }
                    }

                    if let prefsSaveMessage {
                        Text(prefsSaveMessage)
                            .font(.caption)
                            .foregroundStyle(prefsSaveMessage == "Saved." ? Color.secondary : Color.red)
                    }
                }

                Section("Manage") {
                    Button {
                        showClassSchedule = true
                    } label: {
                        Label("Courses & class schedule", systemImage: "calendar.badge.clock")
                    }

                    Button {
                        showFileUpload = true
                    } label: {
                        Label("Upload Syllabus", systemImage: "doc.badge.plus")
                    }
                }

                Section("Debug") {
                    Button {
                        showDebugLog = true
                    } label: {
                        HStack {
                            Label("Error Log", systemImage: "ladybug")
                            Spacer()
                            let count = ErrorLogger.shared.entries.count
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption.monospacedDigit())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(.red)
                                    .background(.red.opacity(0.15), in: Capsule())
                            }
                        }
                    }

                    LabeledContent("API", value: APIClient.shared.baseURL)
                        .font(.caption)
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
            .onAppear {
                loadStudyPreferencesFromProfile()
            }
            .onChange(of: authStore.currentUser?.id) { _, _ in
                loadStudyPreferencesFromProfile()
            }
            .sheet(isPresented: $showClassSchedule) {
                ClassScheduleView()
            }
            .sheet(isPresented: $showFileUpload) {
                FileUploadView(courseId: nil)
            }
            .sheet(isPresented: $showDebugLog) {
                DebugLogView()
            }
        }
    }

    private func loadStudyPreferencesFromProfile() {
        prefsSaveMessage = nil
        let d = AuthStore.preferencesDictionary(from: authStore.currentUser)
        if let s = d["preferredStartTime"] as? String {
            studyStart = Self.timeToday(fromHHmm: s) ?? Self.defaultTime(hour: 9, minute: 0)
        }
        if let s = d["preferredEndTime"] as? String {
            studyEnd = Self.timeToday(fromHHmm: s) ?? Self.defaultTime(hour: 22, minute: 0)
        }
        if let m = d["maxHoursPerDay"] as? Double {
            maxHoursPerDay = m
        } else if let m = d["maxHoursPerDay"] as? Int {
            maxHoursPerDay = Double(m)
        }
        if let b = d["breakDuration"] as? Double {
            breakDuration = b
        } else if let b = d["breakDuration"] as? Int {
            breakDuration = Double(b)
        }
    }

}

// MARK: - Class schedule (courses + locked blocks)

private let classSchedulePresetColors = [
    "#EF4444", "#F97316", "#EAB308", "#22C55E",
    "#06B6D4", "#3B82F6", "#8B5CF6", "#EC4899",
    "#6B7280", "#78716C",
]

struct ClassScheduleView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(\.dismiss) private var dismiss

    @State private var newCourseName = ""
    @State private var newCourseColor = "#6B7280"
    @State private var selectedCourseId: String?
    @State private var selectedWeekdays: Set<Int> = []
    @State private var classLabel = ""
    @State private var classStart = SettingsView.defaultTime(hour: 9, minute: 0)
    @State private var classEnd = SettingsView.defaultTime(hour: 10, minute: 0)
    @State private var repeatUntil = Self.defaultRepeatUntil
    @State private var isAddingClasses = false
    @State private var blockToEdit: ScheduleBlock?
    @State private var courseToEdit: Course?
    @State private var addClassError: String?

    private static var defaultRepeatUntil: Date {
        Calendar.current.date(byAdding: .month, value: 4, to: Date()) ?? Date()
    }

    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private var lockedBlocks: [ScheduleBlock] {
        scheduleStore.blocks.filter(\.isLocked).sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.startTime < $1.startTime
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if taskStore.courses.isEmpty {
                        Text("No courses yet — add one below or when scheduling a class.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(taskStore.courses) { course in
                            Button {
                                courseToEdit = course
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color(hex: course.color))
                                        .frame(width: 12, height: 12)
                                    Text(course.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if let count = course._count?.tasks {
                                        Text("\(count) tasks")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let course = taskStore.courses[index]
                                if selectedCourseId == course.id { selectedCourseId = nil }
                                Task { await taskStore.deleteCourse(id: course.id) }
                            }
                        }
                    }
                } header: {
                    Text("Your courses")
                } footer: {
                    if !taskStore.courses.isEmpty {
                        Text("Tap a course to edit or delete it. You can also swipe left on a course to remove it.")
                    }
                }

                Section("Add course") {
                    TextField("Course name", text: $newCourseName)
                    presetColorGrid(selection: $newCourseColor)
                    Button("Add course") {
                        Task {
                            if let c = await taskStore.createCourse(name: newCourseName, color: newCourseColor) {
                                newCourseName = ""
                                selectedCourseId = c.id
                            }
                        }
                    }
                    .disabled(newCourseName.isEmpty)
                }

                Section("Add class to calendar") {
                    Picker("Course", selection: $selectedCourseId) {
                        Text("Select a course").tag(nil as String?)
                        ForEach(taskStore.courses) { c in
                            Text(c.name).tag(Optional(c.id))
                        }
                    }

                    TextField("Label (optional)", text: $classLabel)
                        .textInputAutocapitalization(.words)

                    ForEach(1...7, id: \.self) { weekday in
                        Toggle(isOn: Binding(
                            get: { selectedWeekdays.contains(weekday) },
                            set: { on in
                                if on { selectedWeekdays.insert(weekday) }
                                else { selectedWeekdays.remove(weekday) }
                            }
                        )) {
                            Text(Self.weekdayName(weekday))
                        }
                    }

                    DatePicker("Starts", selection: $classStart, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $classEnd, displayedComponents: .hourAndMinute)
                    DatePicker("Repeat until", selection: $repeatUntil, in: Date()..., displayedComponents: .date)

                    if let addClassError {
                        Text(addClassError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        addClassesForSelectedDays()
                    } label: {
                        if isAddingClasses {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Adding classes...")
                            }
                        } else {
                            Text("Add to schedule")
                        }
                    }
                    .disabled(selectedCourseId == nil || selectedWeekdays.isEmpty || !timesValid || isAddingClasses)
                }

                Section {
                    if lockedBlocks.isEmpty {
                        Text("No locked blocks yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(lockedBlocks) { block in
                            lockedBlockRow(block)
                                .contentShape(Rectangle())
                                .onTapGesture { blockToEdit = block }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                let id = lockedBlocks[index].id
                                Task { await scheduleStore.deleteBlock(id: id) }
                            }
                        }
                    }
                } header: {
                    Text("Scheduled classes (locked)")
                } footer: {
                    if !lockedBlocks.isEmpty {
                        Text("Tap a class to edit or remove it. Swipe left on a row to delete.")
                    }
                }
            }
            .navigationTitle("Courses & schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $blockToEdit) { block in
                EditLockedBlockSheet(
                    block: block,
                    courses: taskStore.courses,
                    onSave: {
                        blockToEdit = nil
                        Task { await refreshBlocks() }
                    },
                    onCancel: { blockToEdit = nil },
                    onDeleted: {
                        blockToEdit = nil
                        Task { await refreshBlocks() }
                    }
                )
                .environment(scheduleStore)
            }
            .sheet(item: $courseToEdit) { course in
                EditCourseSheet(
                    course: course,
                    onSave: { courseToEdit = nil },
                    onCancel: { courseToEdit = nil },
                    onDeleted: {
                        if selectedCourseId == course.id { selectedCourseId = nil }
                        courseToEdit = nil
                    }
                )
                .environment(taskStore)
            }
            .task {
                await taskStore.fetchCourses()
                await refreshBlocks()
            }
        }
    }

    private var timesValid: Bool {
        StudyScheduleTime.hhmm(from: classStart) < StudyScheduleTime.hhmm(from: classEnd)
    }

    private func lockedBlockRow(_ block: ScheduleBlock) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: block.classCourse?.color ?? "#6B7280"))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.label ?? block.classCourse?.name ?? "Class")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text("\(weekdayLabel(for: block.date)) · \(block.date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(block.startTime)–\(block.endTime)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func weekdayLabel(for ymdString: String) -> String {
        guard let d = Self.ymd.date(from: String(ymdString.prefix(10))) else { return "" }
        return Self.weekdayFormatter.string(from: d)
    }

    private static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let idx = (weekday - 1) % 7
        return symbols[idx]
    }

    private func addClassesForSelectedDays() {
        addClassError = nil
        guard let courseId = selectedCourseId else { return }
        guard let course = taskStore.courses.first(where: { $0.id == courseId }) else { return }
        guard !selectedWeekdays.isEmpty else { return }
        guard timesValid else {
            addClassError = "End time must be after start time."
            return
        }

        let startStr = StudyScheduleTime.hhmm(from: classStart)
        let endStr = StudyScheduleTime.hhmm(from: classEnd)
        let labelText = classLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? course.name
            : classLabel
        let endDate = Calendar.current.startOfDay(for: repeatUntil)

        isAddingClasses = true
        Task {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())

            for weekday in selectedWeekdays.sorted() {
                var cursor = cal.nextDate(
                    after: today,
                    matching: DateComponents(weekday: weekday),
                    matchingPolicy: .nextTimePreservingSmallerComponents
                )
                while let date = cursor, date <= endDate {
                    let request = CreateBlockRequest(
                        taskId: nil,
                        courseId: courseId,
                        date: Self.ymd.string(from: date),
                        startTime: startStr,
                        endTime: endStr,
                        isLocked: true,
                        label: labelText
                    )
                    _ = await scheduleStore.createBlock(request)
                    cursor = cal.date(byAdding: .weekOfYear, value: 1, to: date)
                }
            }

            selectedWeekdays.removeAll()
            classLabel = ""
            isAddingClasses = false
            await refreshBlocks()
        }
    }

    private func refreshBlocks() async {
        let cal = Calendar.current
        let now = Date()
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return }
        guard let end = cal.date(byAdding: .month, value: 3, to: start) else { return }
        await scheduleStore.fetchBlocks(startDate: start, endDate: end)
    }

    @ViewBuilder
    private func presetColorGrid(selection: Binding<String>) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
            ForEach(classSchedulePresetColors, id: \.self) { color in
                Circle()
                    .fill(Color(hex: color))
                    .frame(width: 32, height: 32)
                    .overlay {
                        if color == selection.wrappedValue {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .onTapGesture { selection.wrappedValue = color }
            }
        }
    }
}

// MARK: - Small helpers for ClassScheduleView

private enum StudyScheduleTime {
    static func defaultTime(hour: Int, minute: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour
        c.minute = minute
        return Calendar.current.date(from: c) ?? Date()
    }

    static func hhmm(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func timeToday(fromHHmm s: String) -> Date? {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = parts[0]
        c.minute = parts[1]
        return Calendar.current.date(from: c)
    }
}

// Bridge SettingsView.defaultTime for ClassScheduleView file-private access
extension SettingsView {
    fileprivate static func defaultTime(hour: Int, minute: Int) -> Date {
        StudyScheduleTime.defaultTime(hour: hour, minute: minute)
    }

    fileprivate static func hhmm(from date: Date) -> String {
        StudyScheduleTime.hhmm(from: date)
    }

    fileprivate static func timeToday(fromHHmm s: String) -> Date? {
        StudyScheduleTime.timeToday(fromHHmm: s)
    }

}

// MARK: - Edit locked block

private struct EditLockedBlockSheet: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    let block: ScheduleBlock
    let courses: [Course]
    var onSave: () -> Void
    var onCancel: () -> Void
    var onDeleted: () -> Void

    @State private var label: String
    @State private var date: Date
    @State private var start: Date
    @State private var end: Date
    @State private var selectedCourseId: String?
    @State private var linkCourse: Bool
    @State private var errorText: String?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(
        block: ScheduleBlock,
        courses: [Course],
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onDeleted: @escaping () -> Void
    ) {
        self.block = block
        self.courses = courses
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDeleted = onDeleted
        _label = State(initialValue: block.label ?? "")
        let parsed = Self.ymd.date(from: String(block.date.prefix(10))) ?? Date()
        _date = State(initialValue: parsed)
        _start = State(initialValue: StudyScheduleTime.timeToday(fromHHmm: block.startTime) ?? StudyScheduleTime.defaultTime(hour: 9, minute: 0))
        _end = State(initialValue: StudyScheduleTime.timeToday(fromHHmm: block.endTime) ?? StudyScheduleTime.defaultTime(hour: 10, minute: 0))
        _selectedCourseId = State(initialValue: block.courseId)
        _linkCourse = State(initialValue: block.courseId != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Label", text: $label)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                }

                Section("Course color") {
                    Toggle("Link to course", isOn: $linkCourse)
                    if linkCourse {
                        Picker("Course", selection: $selectedCourseId) {
                            Text("None").tag(nil as String?)
                            ForEach(courses) { c in
                                Text(c.name).tag(Optional(c.id))
                            }
                        }
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(Color.red).font(.caption)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            if isDeleting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Delete from schedule")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isDeleting)
                } footer: {
                    Text("Removes this class block from your calendar. Your course and tasks are not deleted.")
                }
            }
            .navigationTitle("Edit class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isDeleting)
                }
            }
            .alert("Remove this class?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await deleteBlock() }
                }
            } message: {
                Text("This block will be removed from your schedule.")
            }
        }
    }

    private func deleteBlock() async {
        isDeleting = true
        defer { isDeleting = false }
        if await scheduleStore.deleteBlock(id: block.id) {
            onDeleted()
        } else {
            errorText = scheduleStore.error ?? "Could not delete."
        }
    }

    private func save() async {
        errorText = nil
        let startS = StudyScheduleTime.hhmm(from: start)
        let endS = StudyScheduleTime.hhmm(from: end)
        guard startS < endS else {
            errorText = "End time must be after start time."
            return
        }

        var req = UpdateBlockRequest()
        req.label = label.isEmpty ? nil : label
        req.date = Self.ymd.string(from: date)
        req.startTime = startS
        req.endTime = endS
        if linkCourse {
            if let id = selectedCourseId {
                req.courseId = id
                req.setCourseIdNull = false
            } else {
                req.setCourseIdNull = true
            }
        } else {
            req.setCourseIdNull = true
        }

        if await scheduleStore.updateBlock(id: block.id, req) != nil {
            onSave()
        } else {
            errorText = scheduleStore.error ?? "Could not save."
        }
    }
}

// MARK: - Edit course

private struct EditCourseSheet: View {
    @Environment(TaskStore.self) private var taskStore
    let course: Course
    var onSave: () -> Void
    var onCancel: () -> Void
    var onDeleted: () -> Void

    @State private var name: String
    @State private var color: String
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    init(
        course: Course,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onDeleted: @escaping () -> Void
    ) {
        self.course = course
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDeleted = onDeleted
        _name = State(initialValue: course.name)
        _color = State(initialValue: course.color)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                    ForEach(classSchedulePresetColors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 32, height: 32)
                            .overlay {
                                if hex == color {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .onTapGesture { color = hex }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            if isDeleting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Delete course")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isDeleting)
                } footer: {
                    Text("Deleting removes the course. Tasks stay in your list but are no longer linked to this course. Class blocks linked to this course may need to be updated.")
                }
            }
            .navigationTitle("Edit course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDeleting)
                }
            }
            .alert("Delete this course?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await deleteCourse() }
                }
            } message: {
                Text("“\(course.name)” will be removed. This cannot be undone.")
            }
        }
    }

    private func deleteCourse() async {
        isDeleting = true
        defer { isDeleting = false }
        if await taskStore.deleteCourse(id: course.id) {
            onDeleted()
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let changedName = trimmed != course.name
        let changedColor = color != course.color
        guard changedName || changedColor else {
            onSave()
            return
        }
        _ = await taskStore.updateCourse(
            id: course.id,
            name: changedName ? trimmed : nil,
            color: changedColor ? color : nil
        )
        onSave()
    }
}
