import Foundation

struct ReminderTime: Codable, Hashable, Identifiable {
    var id = UUID()
    var hour: Int
    var minute: Int

    var minutesIntoDay: Int { hour * 60 + minute }

    var label: String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

struct ReminderSchedule: Codable, Hashable {
    var isOn = true
    var times: [ReminderTime] = [ReminderTime(hour: 9, minute: 0)]
    /// Calendar weekdays: 1 is Sunday, 7 is Saturday.
    var weekdays: Set<Int> = Set(1...7)

    static let maxTimes = 6

    private var validWeekdays: Set<Int> { weekdays.filter { (1...7).contains($0) } }

    /// Sorted by time of day with duplicates dropped.
    var sortedTimes: [ReminderTime] {
        var seen = Set<Int>()
        return times
            .sorted { $0.minutesIntoDay < $1.minutesIntoDay }
            .filter { seen.insert($0.minutesIntoDay).inserted }
    }

    /// One entry per repeating notification. Every day collapses to one daily trigger per time,
    /// which keeps a few projects well under the 64 pending notifications iOS allows an app.
    func triggerComponents() -> [DateComponents] {
        guard isOn else { return [] }
        let days = validWeekdays.sorted()
        guard !days.isEmpty else { return [] }
        return sortedTimes.flatMap { time -> [DateComponents] in
            if days.count == 7 {
                return [DateComponents(hour: time.hour, minute: time.minute)]
            }
            return days.map { DateComponents(hour: time.hour, minute: time.minute, weekday: $0) }
        }
    }

    // MARK: Display

    /// Weekdays in the order the user's calendar starts its week.
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    var timesSummary: String {
        sortedTimes.map(\.label).joined(separator: ", ")
    }

    var daysSummary: String {
        let days = validWeekdays
        if days.count == 7 { return "Every day" }
        if days.isEmpty { return "No days picked" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return Self.orderedWeekdays()
            .filter { days.contains($0) }
            .map { symbols[$0 - 1] }
            .joined(separator: ", ")
    }

    /// Short enough for a list row.
    var shortSummary: String {
        guard isOn, !times.isEmpty else { return "Off" }
        if validWeekdays.count == 7 { return timesSummary }
        return "\(timesSummary), \(daysSummary)"
    }
}
