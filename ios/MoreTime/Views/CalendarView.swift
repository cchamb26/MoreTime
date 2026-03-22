import SwiftUI

struct CalendarView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(TaskStore.self) private var taskStore
    @State private var selectedDate = Date()
    @State private var showGenerateSheet = false
    @State private var showClearConfirm = false

    private let calendar = Calendar.current

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        // Pre-compute days and blocks-by-date once per render, not per cell
        let days = daysInMonth()
        let blocksByDate = buildBlocksByDateMap()
        let tasksByDueDay = CalendarDueTaskHelpers.tasksByDueDateKey(tasks: taskStore.tasks, calendar: calendar)

        NavigationStack {
            VStack(spacing: 0) {
                // Month navigation
                HStack {
                    Button {
                        withAnimation { moveMonth(by: -1) }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                    }

                    Spacer()

                    Text(Self.monthYearFormatter.string(from: selectedDate))
                        .font(.headline)

                    Spacer()

                    Button {
                        withAnimation { moveMonth(by: 1) }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                // Weekday headers
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
                    ForEach(["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"], id: \.self) { day in
                        Text(day)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)

                // Calendar grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, date in
                        if let date {
                            let dateKey = Self.dayKeyFormatter.string(from: date)
                            let dayBlocks = blocksByDate[dateKey] ?? []
                            let dueOnDay = tasksByDueDay[dateKey] ?? []
                            let dueTasksOnly = CalendarDueTaskHelpers.orphanDueTasks(
                                blocks: dayBlocks,
                                tasksOnDay: dueOnDay
                            )
                            CalendarDayCell(
                                date: date,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                isToday: calendar.isDateInToday(date),
                                blocks: dayBlocks,
                                dueTasksOnly: dueTasksOnly
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedDate = date
                                }
                            }
                        } else {
                            Color.clear
                                .frame(height: 48)
                        }
                    }
                }
                .padding(.horizontal)

                Divider()
                    .padding(.top, 8)

                // Day detail
                DayDetailView(date: selectedDate)
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showGenerateSheet = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Today") {
                        withAnimation { selectedDate = Date() }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Clear Schedule", role: .destructive) {
                        showClearConfirm = true
                    }
                    .disabled(scheduleStore.blocks.filter { !$0.isLocked }.isEmpty)
                }
            }
            .alert("Clear Schedule", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    Task { await scheduleStore.clearAllBlocks() }
                }
            } message: {
                Text("This will remove all generated schedule blocks. Locked blocks (classes, work, etc.) will be kept. This cannot be undone.")
            }
            .sheet(isPresented: $showGenerateSheet) {
                ScheduleGenerateView()
            }
            .navigationDestination(for: TaskItem.self) { task in
                TaskDetailView(task: task)
            }
        }
    }

    /// Build a dictionary keyed by "yyyy-MM-dd" to avoid per-cell filter+sort
    private func buildBlocksByDateMap() -> [String: [ScheduleBlock]] {
        var map: [String: [ScheduleBlock]] = [:]
        for block in scheduleStore.blocks {
            let key = String(block.date.prefix(10))
            map[key, default: []].append(block)
        }
        // Sort each day's blocks by startTime once
        for key in map.keys {
            map[key]?.sort { $0.startTime < $1.startTime }
        }
        return map
    }

    private func moveMonth(by value: Int) {
        if let newDate = calendar.date(byAdding: .month, value: value, to: selectedDate) {
            selectedDate = newDate
            Task {
                let start = calendar.date(from: calendar.dateComponents([.year, .month], from: newDate))!
                let end = calendar.date(byAdding: .month, value: 1, to: start)!
                await scheduleStore.fetchBlocks(startDate: start, endDate: end)
            }
        }
    }

    private func daysInMonth() -> [Date?] {
        let components = calendar.dateComponents([.year, .month], from: selectedDate)
        let firstDay = calendar.date(from: components)!
        let weekday = calendar.component(.weekday, from: firstDay)
        let range = calendar.range(of: .day, in: .month, for: firstDay)!

        var days: [Date?] = Array(repeating: nil, count: weekday - 1)
        for day in range {
            var comp = components
            comp.day = day
            days.append(calendar.date(from: comp))
        }

        // Pad to complete week
        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }
}

struct CalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let blocks: [ScheduleBlock]
    /// Due tasks on this day that are not already shown via a schedule block (`task_id`).
    let dueTasksOnly: [TaskItem]

    private let calendar = Calendar.current

    private var blockIndicators: [ScheduleBlock] { Array(blocks.prefix(3)) }
    private var taskIndicators: [TaskItem] {
        Array(dueTasksOnly.prefix(max(0, 3 - blockIndicators.count)))
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(.callout, design: .rounded, weight: isToday ? .bold : .regular))
                .foregroundStyle(isSelected ? Color(.systemBackground) : isToday ? Color.primary : Color.primary.opacity(0.8))

            // Block circles + task-only squares (deduped vs blocks)
            HStack(spacing: 2) {
                ForEach(blockIndicators) { block in
                    Circle()
                        .fill(Color(hex: block.task?.course?.color ?? block.classCourse?.color ?? "#6B7280"))
                        .frame(width: 4, height: 4)
                }
                ForEach(taskIndicators) { task in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: task.course?.color ?? "#6B7280"))
                        .frame(width: 4, height: 4)
                }
            }
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.primary)
            } else if isToday {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.primary.opacity(0.3), lineWidth: 1)
            }
        }
    }
}

struct DayDetailView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(TaskStore.self) private var taskStore

    let date: Date

    private let calendar = Calendar.current

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    var body: some View {
        let blocks = scheduleStore.blocksForDate(date)
        let dateKey = CalendarDueTaskHelpers.dayKey(for: date, calendar: calendar)
        let tasksByDueDay = CalendarDueTaskHelpers.tasksByDueDateKey(tasks: taskStore.tasks, calendar: calendar)
        let dueOnDay = tasksByDueDay[dateKey] ?? []
        let orphanDueTasks = CalendarDueTaskHelpers.orphanDueTasks(blocks: blocks, tasksOnDay: dueOnDay)

        VStack(alignment: .leading, spacing: 0) {
            Text(Self.dayFormatter.string(from: date))
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 12)

            if blocks.isEmpty, orphanDueTasks.isEmpty {
                ContentUnavailableView {
                    Label("Nothing on this day", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Add tasks with a due date, generate a schedule, or add class blocks in Settings")
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if !blocks.isEmpty {
                            Text("Scheduled")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                            ForEach(blocks) { block in
                                ScheduleBlockCard(block: block)
                            }
                        }

                        if !orphanDueTasks.isEmpty {
                            Text("Due")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.top, blocks.isEmpty ? 0 : 4)

                            ForEach(orphanDueTasks) { task in
                                NavigationLink(value: task) {
                                    TaskDueRow(task: task)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct ScheduleBlockCard: View {
    let block: ScheduleBlock
    @State private var isExpanded = false

    private var durationMinutes: Int {
        let parts = { (s: String) -> Int in
            let p = s.split(separator: ":").compactMap { Int($0) }
            return (p.first ?? 0) * 60 + (p.last ?? 0)
        }
        return parts(block.endTime) - parts(block.startTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .trailing) {
                    Text(block.startTime)
                        .font(.caption.monospacedDigit())
                    Text(block.endTime)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(width: 44)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: block.classCourse?.color ?? block.task?.course?.color ?? "#6B7280"))
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(block.isLocked
                        ? (block.label ?? block.classCourse?.name ?? "Class")
                        : (block.task?.title ?? block.label ?? "Block"))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(isExpanded ? nil : 1)

                    if let courseName = block.classCourse?.name ?? block.task?.course?.name {
                        Text(courseName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if block.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(12)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 8) {
                    if let label = block.label, !label.isEmpty {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }

                    HStack(spacing: 16) {
                        Label("\(durationMinutes) min", systemImage: "clock")
                        if let p = block.task?.priority {
                            Label("P\(p)", systemImage: "flag")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        }
    }
}

// MARK: - Due tasks merged into calendar

private enum CalendarDueTaskHelpers {
    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoInternetDateTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDueDate(_ string: String) -> Date? {
        if let d = isoWithFractional.date(from: string) { return d }
        return isoInternetDateTime.date(from: string)
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func dueDayKey(forDueString string: String, calendar: Calendar) -> String? {
        guard let date = parseDueDate(string) else { return nil }
        return dayKey(for: date, calendar: calendar)
    }

    static func tasksByDueDateKey(tasks: [TaskItem], calendar: Calendar) -> [String: [TaskItem]] {
        var map: [String: [TaskItem]] = [:]
        for task in tasks {
            guard task.status != "completed",
                  let due = task.dueDate,
                  let key = dueDayKey(forDueString: due, calendar: calendar) else { continue }
            map[key, default: []].append(task)
        }
        for key in map.keys {
            map[key]?.sort { lhs, rhs in
                let l = lhs.dueDate.flatMap { parseDueDate($0) } ?? .distantFuture
                let r = rhs.dueDate.flatMap { parseDueDate($0) } ?? .distantFuture
                return l < r
            }
        }
        return map
    }

    static func orphanDueTasks(blocks: [ScheduleBlock], tasksOnDay: [TaskItem]) -> [TaskItem] {
        var linked = Set<String>()
        for block in blocks {
            if let tid = block.taskId { linked.insert(tid) }
            if let tid = block.task?.id { linked.insert(tid) }
        }
        return tasksOnDay.filter { !linked.contains($0.id) }
    }
}

private struct TaskDueRow: View {
    let task: TaskItem

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                if let due = task.dueDate, let parsed = CalendarDueTaskHelpers.parseDueDate(due) {
                    Text(Self.timeFormatter.string(from: parsed))
                        .font(.caption.monospacedDigit())
                } else {
                    Text("—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("due")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: task.course?.color ?? "#6B7280"))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)

                if let courseName = task.course?.name {
                    Text(courseName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}
