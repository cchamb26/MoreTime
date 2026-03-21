import SwiftUI

struct CalendarView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
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
                            CalendarDayCell(
                                date: date,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                isToday: calendar.isDateInToday(date),
                                blocks: blocksByDate[dateKey] ?? []
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

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(.callout, design: .rounded, weight: isToday ? .bold : .regular))
                .foregroundStyle(isSelected ? Color(.systemBackground) : isToday ? Color.primary : Color.primary.opacity(0.8))

            // Block indicators
            HStack(spacing: 2) {
                ForEach(blocks.prefix(3), id: \.id) { block in
                    Circle()
                        .fill(Color(hex: block.task?.course?.color ?? "#6B7280"))
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
    let date: Date

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    var body: some View {
        let blocks = scheduleStore.blocksForDate(date)

        VStack(alignment: .leading, spacing: 0) {
            Text(Self.dayFormatter.string(from: date))
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 12)

            if blocks.isEmpty {
                ContentUnavailableView {
                    Label("No blocks scheduled", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Generate a schedule or add blocks manually")
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(blocks) { block in
                            ScheduleBlockCard(block: block)
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
                    .fill(Color(hex: block.task?.course?.color ?? "#6B7280"))
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(block.task?.title ?? block.label ?? "Block")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(isExpanded ? nil : 1)

                    if let courseName = block.task?.course?.name {
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
