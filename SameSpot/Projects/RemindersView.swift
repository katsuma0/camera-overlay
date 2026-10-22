import SwiftUI

struct RemindersView: View {
    let projectID: UUID

    @EnvironmentObject private var store: ProjectStore
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var schedule: ReminderSchedule
    @State private var notificationsDenied = false

    init(projectID: UUID, initial: ReminderSchedule) {
        self.projectID = projectID
        _schedule = State(initialValue: initial)
    }

    var body: some View {
        Form {
            if notificationsDenied && schedule.isOn {
                Section {
                    Label("Notifications are off for Same Spot, so these won't show up.", systemImage: "bell.slash")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }
            ReminderEditorSections(schedule: $schedule)
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: schedule) { oldValue, newValue in
            store.setReminders(newValue, for: projectID)
            if newValue.isOn && !oldValue.isOn {
                let store = self.store
                NotificationScheduler.requestAuthorization { granted in
                    if granted { NotificationScheduler.sync(store.projects) }
                    notificationsDenied = !granted
                }
            }
        }
        // Checked again on return from Settings, where the user may have just turned them on.
        .task(id: scenePhase) {
            if scenePhase == .active {
                notificationsDenied = await NotificationScheduler.isDenied()
            }
        }
    }
}

/// The on switch, the times, and the days. Shared by New Project and Reminders.
struct ReminderEditorSections: View {
    @Binding var schedule: ReminderSchedule

    var body: some View {
        Section {
            Toggle("Remind Me", isOn: $schedule.isOn)
        } footer: {
            Text("You get a notification at each time on the days you pick. Tap it and the camera opens on this project.")
        }

        if schedule.isOn {
            Section("Times") {
                ForEach($schedule.times) { $time in
                    DatePicker("Time", selection: dateBinding(for: $time), displayedComponents: .hourAndMinute)
                }
                .onDelete { offsets in
                    schedule.times.remove(atOffsets: offsets)
                }
                .deleteDisabled(schedule.times.count <= 1)

                if schedule.times.count < ReminderSchedule.maxTimes {
                    Button {
                        addTime()
                    } label: {
                        Label("Add Time", systemImage: "plus")
                    }
                }
            }

            Section {
                WeekdayPicker(selection: $schedule.weekdays)
            } header: {
                Text("Repeat")
            } footer: {
                Text(schedule.daysSummary)
            }
        }
    }

    private func dateBinding(for time: Binding<ReminderTime>) -> Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: time.wrappedValue.hour,
                minute: time.wrappedValue.minute,
                second: 0,
                of: Date()
            ) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            time.wrappedValue.hour = parts.hour ?? 9
            time.wrappedValue.minute = parts.minute ?? 0
        }
    }

    /// Morning and evening first, since that's what most people want.
    private func addTime() {
        let taken = Set(schedule.times.map(\.minutesIntoDay))
        let suggestions: [(hour: Int, minute: Int)] = [(20, 0), (9, 0), (13, 0), (7, 0), (17, 0), (22, 0)]
        let pick = suggestions.first { !taken.contains($0.hour * 60 + $0.minute) } ?? (hour: 12, minute: 0)
        schedule.times.append(ReminderTime(hour: pick.hour, minute: pick.minute))
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ReminderSchedule.orderedWeekdays(), id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    toggle(day)
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            Circle().fill(isOn ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    /// The last day can't be turned off. No days at all would be a reminder that never fires.
    private func toggle(_ day: Int) {
        if selection.contains(day) {
            if selection.count > 1 {
                selection.remove(day)
            }
        } else {
            selection.insert(day)
        }
    }
}
