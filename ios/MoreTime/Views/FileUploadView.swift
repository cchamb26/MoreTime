import SwiftUI
import UniformTypeIdentifiers

struct FileUploadView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(\.dismiss) private var dismiss

    let courseId: String?

    @State private var isPickerPresented = false
    @State private var uploadedFiles: [FileUploadResponse] = []
    @State private var isUploading = false
    @State private var isExtracting = false
    @State private var extractedTasks: [TaskItem] = []
    @State private var error: String?

    private let api = APIClient.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                contentView

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Upload Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [.pdf, .plainText, .png, .jpeg,
                    UTType(filenameExtension: "docx") ?? .data],
                allowsMultipleSelection: true
            ) { result in
                Task { await handleFileSelection(result) }
            }
            .overlay {
                if isUploading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Uploading...")
                        .padding(24)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if uploadedFiles.isEmpty && extractedTasks.isEmpty {
            uploadPromptView
        } else if !extractedTasks.isEmpty {
            extractedTasksView
        } else {
            uploadedFilesView
        }
    }

    private var uploadPromptView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Upload Syllabus or Documents")
                .font(.headline)

            Text("Supports PDF, DOCX, TXT, and images")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                isPickerPresented = true
            } label: {
                Label("Choose Files", systemImage: "folder")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var extractedTasksView: some View {
        List {
            Section("Extracted Tasks (\(extractedTasks.count))") {
                ForEach(extractedTasks) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.subheadline.weight(.medium))
                        HStack {
                            if let due = task.dueDate {
                                Text(due.prefix(10))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(task.estimatedHours, specifier: "%.1f")h")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var uploadedFilesView: some View {
        List {
            Section("Uploaded Files") {
                ForEach(uploadedFiles) { file in
                    uploadedFileRow(file)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func uploadedFileRow(_ file: FileUploadResponse) -> some View {
        HStack {
            Image(systemName: iconForMime(file.mimeType))
            VStack(alignment: .leading) {
                Text(file.originalName)
                    .font(.subheadline)
                Text(file.parseStatus.capitalized)
                    .font(.caption)
                    .foregroundStyle(file.parseStatus == "completed" ? .green : .secondary)
            }
            Spacer()
            if file.parseStatus == "parsing" {
                ProgressView()
            } else if file.parseStatus == "completed" {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
        }
        if !uploadedFiles.isEmpty && extractedTasks.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await extractTasks() }
                } label: {
                    if isExtracting {
                        ProgressView()
                    } else {
                        Text("Extract Tasks")
                    }
                }
                .disabled(isExtracting || uploadedFiles.allSatisfy { $0.parseStatus != "completed" })
            }
        }
        if !extractedTasks.isEmpty {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    Task {
                        await taskStore.fetchTasks()
                        dismiss()
                    }
                }
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result else { return }
        isUploading = true
        defer { isUploading = false }

        // Read file data and release security-scoped access before async upload
        struct FilePayload {
            let data: Data
            let fileName: String
            let mimeType: String
        }

        var payloads: [FilePayload] = []
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) {
                payloads.append(FilePayload(data: data, fileName: url.lastPathComponent, mimeType: mimeType(for: url)))
            }
        }

        // Upload all files in parallel
        var fields: [String: String] = [:]
        if let courseId { fields["courseId"] = courseId }

        await withTaskGroup(of: Result<[FileUploadResponse], Error>.self) { group in
            for payload in payloads {
                group.addTask {
                    do {
                        let files: [FileUploadResponse] = try await self.api.upload(
                            path: "/files/upload",
                            fileData: payload.data,
                            fileName: payload.fileName,
                            mimeType: payload.mimeType,
                            additionalFields: fields
                        )
                        return .success(files)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let files):
                    uploadedFiles.append(contentsOf: files)
                case .failure(let err):
                    self.error = err.localizedDescription
                }
            }
        }

        // Poll for parse completion
        await pollParseStatus()
    }

    private func pollParseStatus() async {
        for _ in 0..<30 { // Max 30 attempts, 2s each
            try? await Task.sleep(for: .seconds(2))

            // Gather IDs of files still pending on the main actor,
            // then fetch updates concurrently off the main actor.
            let pendingFiles = uploadedFiles.enumerated().filter {
                $0.element.parseStatus == "pending" || $0.element.parseStatus == "parsing"
            }
            guard !pendingFiles.isEmpty else { break }

            let updates: [(Int, FileUploadResponse)] = await withTaskGroup(of: (Int, FileUploadResponse?).self) { group in
                for (i, file) in pendingFiles {
                    group.addTask {
                        let updated: FileUploadResponse? = try? await self.api.request("GET", path: "/files/\(file.id)")
                        return (i, updated)
                    }
                }
                var results: [(Int, FileUploadResponse)] = []
                for await (i, updated) in group {
                    if let updated { results.append((i, updated)) }
                }
                return results
            }

            for (i, updated) in updates {
                uploadedFiles[i] = updated
            }

            let allDone = uploadedFiles.allSatisfy { $0.parseStatus != "pending" && $0.parseStatus != "parsing" }
            if allDone { break }
        }
    }

    private func extractTasks() async {
        isExtracting = true
        defer { isExtracting = false }

        let completedFiles = uploadedFiles.filter { $0.parseStatus == "completed" }

        await withTaskGroup(of: Result<[TaskItem], Error>.self) { group in
            for file in completedFiles {
                group.addTask {
                    do {
                        let result: ExtractTasksResponse = try await self.api.request("POST", path: "/files/\(file.id)/extract-tasks")
                        return .success(result.tasks)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let tasks):
                    extractedTasks.append(contentsOf: tasks)
                case .failure(let err):
                    self.error = err.localizedDescription
                }
            }
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "txt": return "text/plain"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
        }
    }

    private func iconForMime(_ mime: String) -> String {
        if mime.contains("pdf") { return "doc.fill" }
        if mime.contains("word") || mime.contains("docx") { return "doc.richtext.fill" }
        if mime.contains("image") { return "photo.fill" }
        return "doc.text.fill"
    }
}
