import SwiftUI
import UniformTypeIdentifiers

struct SemesterHeatMapView: View {
    @Environment(SemesterStore.self) private var store
    @Environment(TaskStore.self) private var taskStore

    @State private var isPickerPresented = false
    @State private var selectedFiles: [SelectedFile] = []
    @State private var semesterStart = Self.defaultSemesterStart
    @State private var semesterEnd = Self.defaultSemesterEnd
    @State private var showExistingFiles = false
    @State private var showApplyConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan = store.semesterPlan {
                    heatMapView(plan)
                } else {
                    setupView
                }
            }
            .navigationTitle("Semester")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [.pdf, .plainText,
                    UTType(filenameExtension: "docx") ?? .data],
                allowsMultipleSelection: true
            ) { result in
                handleFilePick(result)
            }
            .sheet(isPresented: $showExistingFiles) {
                existingFilesSheet
            }
        }
    }

    // MARK: - Setup Phase

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary.opacity(0.5))

                Text("Semester Heat Map")
                    .font(.title2.bold())

                Text("Upload multiple syllabi to visualize your entire semester workload at a glance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                datePickerSection

                fileListSection

                actionButtons

                if let error = store.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer()
            }
        }
    }

    private var datePickerSection: some View {
        VStack(spacing: 12) {
            DatePicker("Semester Start", selection: $semesterStart, displayedComponents: .date)
            DatePicker("Semester End", selection: $semesterEnd, displayedComponents: .date)
        }
        .padding()
        .background(.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var fileListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Syllabi")
                    .font(.headline)
                Spacer()
                Text("\(selectedFiles.count) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            if selectedFiles.isEmpty {
                Text("No syllabi selected yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach($selectedFiles) { $file in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.fileName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            TextField("Course name", text: $file.courseName)
                                .font(.subheadline)
                                .textFieldStyle(.plain)
                        }

                        Spacer()

                        Button {
                            selectedFiles.removeAll { $0.id == file.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.vertical, 12)
        .background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    isPickerPresented = true
                } label: {
                    Label("Upload New", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)

                Button {
                    showExistingFiles = true
                } label: {
                    Label("From Library", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            Button {
                Task { await generatePlan() }
            } label: {
                if store.isLoading || store.isUploading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(store.isUploading ? "Uploading..." : "Generating...")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    Text("Generate Semester Plan")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(selectedFiles.isEmpty || store.isLoading || store.isUploading)
            .padding(.horizontal)
        }
    }

    // MARK: - Heat Map Phase

    private func heatMapView(_ plan: SemesterPlan) -> some View {
        VStack(spacing: 0) {
            crunchBanner(plan.crunchWeeks)
            legendBar
            summaryBar(plan)
            applyBar

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(plan.weeks) { week in
                        WeekRow(week: week)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .alert("Apply to Calendar", isPresented: $showApplyConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Apply All") {
                Task {
                    let count = await store.applyToCalendar()
                    if count > 0 { await taskStore.fetchTasks() }
                }
            }
        } message: {
            let total = plan.weeks.reduce(0) { $0 + $1.events.count }
            Text("This will create \(total) tasks from your semester plan. You can then generate a study schedule from the Calendar tab.")
        }
    }

    private var applyBar: some View {
        Group {
            if store.appliedCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(store.appliedCount) tasks added to calendar")
                        .font(.caption.weight(.medium))
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.green.opacity(0.08))
            } else {
                Button {
                    showApplyConfirm = true
                } label: {
                    if store.isApplying {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Adding tasks...")
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    } else {
                        Label("Apply to Calendar", systemImage: "calendar.badge.plus")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .disabled(store.isApplying)
                .background(.primary.opacity(0.06))
            }
        }
    }

    private func crunchBanner(_ crunchWeeks: [String]) -> some View {
        Group {
            if !crunchWeeks.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("\(crunchWeeks.count) brutal week\(crunchWeeks.count == 1 ? "" : "s") ahead")
                        .font(.caption.bold())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.red)
            }
        }
    }

    private var legendBar: some View {
        HStack(spacing: 12) {
            ForEach(LegendItem.all, id: \.label) { item in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.color)
                        .frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.label)
                            .font(.caption2.bold())
                        Text(item.hours)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func summaryBar(_ plan: SemesterPlan) -> some View {
        HStack {
            Label("\(plan.totalEvents) events", systemImage: "list.bullet")
            Spacer()
            let totalHours = plan.weeks.reduce(0.0) { $0 + $1.totalEstimatedHours }
            Label(String(format: "%.0fh total", totalHours), systemImage: "clock")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Existing Files Sheet

    private var existingFilesSheet: some View {
        NavigationStack {
            ExistingFilesPickerView(selectedFiles: $selectedFiles) {
                showExistingFiles = false
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if store.semesterPlan != nil {
            ToolbarItem(placement: .cancellationAction) {
                Menu {
                    Button {
                        store.reset()
                        selectedFiles.removeAll()
                    } label: {
                        Label("New Plan", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Actions

    private func handleFilePick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) {
                let name = url.deletingPathExtension().lastPathComponent
                selectedFiles.append(SelectedFile(
                    fileName: url.lastPathComponent,
                    courseName: name,
                    fileData: data,
                    mimeType: mimeType(for: url),
                    existingFileId: nil
                ))
            }
        }
    }

    private func generatePlan() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let startStr = formatter.string(from: semesterStart)
        let endStr = formatter.string(from: semesterEnd)

        let needsUpload = selectedFiles.filter { $0.existingFileId == nil }
        var fileIds = selectedFiles.compactMap(\.existingFileId)

        if !needsUpload.isEmpty {
            let payloads = needsUpload.map { (data: $0.fileData!, fileName: $0.fileName, mimeType: $0.mimeType) }
            let uploaded = await store.uploadFiles(payloads: payloads)

            // Poll until parsed
            var pendingIds = uploaded.map(\.id)
            fileIds.append(contentsOf: pendingIds)

            for _ in 0..<30 {
                if pendingIds.isEmpty { break }
                try? await Task.sleep(for: .seconds(2))
                await store.fetchUploadedFiles()
                let completed = Set(store.uploadedFiles.filter { $0.parseStatus == "completed" }.map(\.id))
                pendingIds = pendingIds.filter { !completed.contains($0) }
            }
        }

        guard !fileIds.isEmpty else { return }
        await store.generatePlan(fileIds: fileIds, start: startStr, end: endStr)
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Defaults

    private static var defaultSemesterStart: Date {
        let cal = Calendar.current
        let now = Date()
        let month = cal.component(.month, from: now)
        let year = cal.component(.year, from: now)
        if month >= 8 {
            return cal.date(from: DateComponents(year: year, month: 8, day: 25))!
        } else {
            return cal.date(from: DateComponents(year: year, month: 1, day: 15))!
        }
    }

    private static var defaultSemesterEnd: Date {
        let cal = Calendar.current
        let now = Date()
        let month = cal.component(.month, from: now)
        let year = cal.component(.year, from: now)
        if month >= 8 {
            return cal.date(from: DateComponents(year: year, month: 12, day: 15))!
        } else {
            return cal.date(from: DateComponents(year: year, month: 5, day: 10))!
        }
    }
}

// MARK: - Supporting Types

struct SelectedFile: Identifiable {
    let id = UUID()
    let fileName: String
    var courseName: String
    let fileData: Data?
    let mimeType: String
    let existingFileId: String?
}

struct LegendItem {
    let label: String
    let hours: String
    let color: Color

    static let all: [LegendItem] = [
        LegendItem(label: "Low", hours: "0–5h", color: .green.opacity(0.3)),
        LegendItem(label: "Medium", hours: "5–10h", color: .yellow.opacity(0.6)),
        LegendItem(label: "High", hours: "10–15h", color: .orange.opacity(0.8)),
        LegendItem(label: "Critical", hours: "15h+", color: .red),
    ]
}

// MARK: - Week Row

struct WeekRow: View {
    let week: SemesterWeek
    @State private var isExpanded = false

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(intensityColor(week.intensity))
                        .frame(width: 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(weekRange)
                            .font(.subheadline.weight(.medium))
                        Text("\(week.events.count) event\(week.events.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(String(format: "%.1fh", week.totalEstimatedHours))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(intensityColor(week.intensity))

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(intensityColor(week.intensity).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            if isExpanded && !week.events.isEmpty {
                VStack(spacing: 0) {
                    ForEach(week.events) { event in
                        HStack(spacing: 10) {
                            Image(systemName: iconForType(event.type))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(.caption)
                                    .lineLimit(2)
                                Text(event.courseName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(formatDate(event.dueDate))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1fh", event.estimatedHours))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 4)
                .background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .padding(.leading, 18)
            }
        }
    }

    private var weekRange: String {
        guard let start = Self.parseDate(week.weekStart),
              let end = Self.parseDate(week.weekEnd) else {
            return "\(week.weekStart) – \(week.weekEnd)"
        }
        return "\(Self.displayFormatter.string(from: start)) – \(Self.displayFormatter.string(from: end))"
    }

    private func formatDate(_ dateStr: String) -> String {
        guard let date = Self.parseDate(dateStr) else { return dateStr }
        return Self.displayFormatter.string(from: date)
    }

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func parseDate(_ str: String) -> Date? {
        isoDateFormatter.date(from: str)
    }

    private func iconForType(_ type: String) -> String {
        switch type.lowercased() {
        case "exam": return "pencil.and.list.clipboard"
        case "quiz": return "questionmark.circle"
        case "homework", "assignment": return "doc.text"
        case "project": return "hammer"
        case "paper": return "text.document"
        case "lab": return "flask"
        case "presentation": return "person.and.background.dotted"
        default: return "calendar"
        }
    }
}

func intensityColor(_ intensity: String) -> Color {
    switch intensity {
    case "low": return .green.opacity(0.3)
    case "medium": return .yellow.opacity(0.6)
    case "high": return .orange.opacity(0.8)
    case "critical": return .red
    default: return .gray.opacity(0.2)
    }
}

// MARK: - Existing Files Picker

private enum LibraryDateFilterMode: String, CaseIterable, Identifiable {
    case all = "All"
    case last7Days = "Last 7 days"
    case last30Days = "Last 30 days"
    case custom = "Custom range"

    var id: String { rawValue }
}

struct ExistingFilesPickerView: View {
    @Environment(SemesterStore.self) private var store
    @Binding var selectedFiles: [SelectedFile]
    let onDismiss: () -> Void

    @State private var selected: Set<String> = []
    @State private var filterMode: LibraryDateFilterMode = .all
    @State private var customRangeStart = Calendar.current.startOfDay(for: Date())
    @State private var customRangeEnd = Calendar.current.startOfDay(for: Date())
    @State private var showCustomRangeSheet = false
    @State private var showDeleteConfirmation = false
    @State private var pendingDeleteId: String?
    @State private var pendingDeleteName = ""
    @State private var deletingIds: Set<String> = []

    private var filteredFiles: [FileUploadResponse] {
        let cal = Calendar.current
        let now = Date()
        switch filterMode {
        case .all:
            return store.uploadedFiles
        case .last7Days:
            guard let start = cal.date(byAdding: .day, value: -7, to: now) else { return [] }
            return store.uploadedFiles.filter { file in
                guard let d = Self.parseUploadedAt(file.createdAt) else { return false }
                return d >= start && d <= now
            }
        case .last30Days:
            guard let start = cal.date(byAdding: .day, value: -30, to: now) else { return [] }
            return store.uploadedFiles.filter { file in
                guard let d = Self.parseUploadedAt(file.createdAt) else { return false }
                return d >= start && d <= now
            }
        case .custom:
            let rangeStart = cal.startOfDay(for: customRangeStart)
            guard let endExclusive = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: customRangeEnd)) else {
                return []
            }
            return store.uploadedFiles.filter { file in
                guard let d = Self.parseUploadedAt(file.createdAt) else { return false }
                return d >= rangeStart && d < endExclusive
            }
        }
    }

    var body: some View {
        Group {
            if store.uploadedFiles.isEmpty {
                ContentUnavailableView(
                    "No files yet",
                    systemImage: "folder",
                    description: Text("Upload syllabi first, then pick them here.")
                )
            } else if filteredFiles.isEmpty {
                ContentUnavailableView(
                    "No files in this range",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Try a different date filter or choose “All”.")
                )
            } else {
                List(filteredFiles) { file in
                    Button {
                        if selected.contains(file.id) {
                            selected.remove(file.id)
                        } else {
                            selected.insert(file.id)
                        }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(file.id) ? .primary : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.originalName)
                                    .font(.subheadline)
                                Text(Self.formatUploadedAt(file.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if deletingIds.contains(file.id) {
                                ProgressView()
                                    .scaleEffect(0.85)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(deletingIds.contains(file.id))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeleteId = file.id
                            pendingDeleteName = file.originalName
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(deletingIds.contains(file.id))
                    }
                }
            }
        }
        .navigationTitle("Select Files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onDismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Uploaded", selection: $filterMode) {
                        ForEach(LibraryDateFilterMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    if filterMode == .custom {
                        Button("Edit date range") {
                            showCustomRangeSheet = true
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add \(selected.count)") {
                    for file in store.uploadedFiles where selected.contains(file.id) {
                        let name = String(file.originalName.split(separator: ".").first ?? Substring(file.originalName))
                        selectedFiles.append(SelectedFile(
                            fileName: file.originalName,
                            courseName: name,
                            fileData: nil,
                            mimeType: file.mimeType,
                            existingFileId: file.id
                        ))
                    }
                    onDismiss()
                }
                .disabled(selected.isEmpty)
            }
        }
        .onChange(of: filterMode) { _, newValue in
            if newValue == .custom {
                showCustomRangeSheet = true
            }
        }
        .sheet(isPresented: $showCustomRangeSheet) {
            NavigationStack {
                Form {
                    DatePicker("From", selection: $customRangeStart, displayedComponents: .date)
                    DatePicker("To", selection: $customRangeEnd, displayedComponents: .date)
                }
                .navigationTitle("Date range")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showCustomRangeSheet = false }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete from library?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete “\(pendingDeleteName)”", role: .destructive) {
                let id = pendingDeleteId
                showDeleteConfirmation = false
                pendingDeleteId = nil
                pendingDeleteName = ""
                if let id {
                    Task { await performDelete(id: id) }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteId = nil
                pendingDeleteName = ""
            }
        } message: {
            Text("This removes the file from your library. It cannot be undone.")
        }
        .task {
            await store.fetchUploadedFiles()
        }
    }

    private func performDelete(id: String) async {
        await MainActor.run { deletingIds.insert(id) }
        let ok = await store.deleteUploadedFile(id: id)
        await MainActor.run {
            deletingIds.remove(id)
            if ok {
                selected.remove(id)
                selectedFiles.removeAll { $0.existingFileId == id }
            }
        }
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let uploadedDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static func parseUploadedAt(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let d = iso8601Fractional.date(from: string) { return d }
        return iso8601.date(from: string)
    }

    private static func formatUploadedAt(_ string: String?) -> String {
        guard let date = parseUploadedAt(string) else { return "Unknown date" }
        return uploadedDisplayFormatter.string(from: date)
    }
}
