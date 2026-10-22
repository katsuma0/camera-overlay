#if DEBUG
import Foundation

extension ProjectStore {
    /// Launch with the -demo argument to start with three weeks of a maple turning red.
    /// The simulator has no camera, so this is the quickest way to try the library and video export.
    func seedDemoProjectIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-demo"), projects.isEmpty else { return }

        var reminders = ReminderSchedule()
        reminders.times = [ReminderTime(hour: 8, minute: 0), ReminderTime(hour: 20, minute: 0)]
        let project = createProject(name: "Back Porch Maple", reminders: reminders)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = 21
        for day in 0..<days {
            guard let morning = calendar.date(byAdding: .day, value: day - (days - 1), to: today),
                  let photo = SimulatedCamera.photo(
                      angle: 90,
                      progress: Double(day) / Double(days - 1),
                      seed: day,
                      date: morning.addingTimeInterval(8 * 3600)
                  ) else { continue }
            if day == 0 {
                _ = try? setTemplate(photo, for: project.id)
            } else {
                _ = try? addFrame(photo, to: project.id)
            }
        }
    }
}
#endif
