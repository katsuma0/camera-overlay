import SwiftUI

struct NewProjectView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var reminders = ReminderSchedule()
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Back porch maple"))
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { if !trimmedName.isEmpty { create() } }
                } footer: {
                    Text("One project is one spot. Next you take the original photo, and every photo after lines up with it.")
                }
                ReminderEditorSections(schedule: $reminders)
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { create() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear { nameFocused = true }
        }
    }

    private func create() {
        let project = store.createProject(name: trimmedName, reminders: reminders)
        if reminders.isOn {
            let store = self.store
            NotificationScheduler.requestAuthorization { granted in
                if granted { NotificationScheduler.sync(store.projects) }
            }
        }
        // The camera tab sees a project with no original and asks for one.
        router.openCamera(for: project.id)
        dismiss()
    }
}
