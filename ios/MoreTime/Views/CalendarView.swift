import SwiftUI

struct CalendarView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var selectedDate = Date()
    @State private var showGenerateSheet = false

    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    var body: some View {
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

                    Text(dateFormatter.string(from: selectedDate))
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
                    ForEach(daysInMonth(), id: \.self) { date in
                        if let date {
                            CalendarDayCell(
                                date: date,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                isToday: calendar.isDateInToday(date),
                                blocks: scheduleStore.blocksForDate(date)
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
            }
            .sheet(isPresented: $showGenerateSheet) {
                ScheduleGenerateView()
            }
        }
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

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    var body: some View {
        let blocks = scheduleStore.blocksForDate(date)

        VStack(alignment: .leading, spacing: 0) {
            Text(dayFormatter.string(from: date))
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

    var body: some View {
        HStack(spacing: 12) {
            // Time
            VStack(alignment: .trailing) {
                Text(block.startTime)
                    .font(.caption.monospacedDigit())
                Text(block.endTime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44)

            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: block.task?.course?.color ?? "#6B7280"))
                .frame(width: 4)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(block.task?.title ?? block.label ?? "Block")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

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
        }
        .padding(12)
        .background(.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
