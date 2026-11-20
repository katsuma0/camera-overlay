import SwiftUI

/// Same words as PRIVACY.md, which is the policy link on the App Store page.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Part: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    private let sections: [Part] = [
        Part(title: "Your data", body: "Everything you add, including photos, projects and reminders, is stored only on your device. It is never sent to us or to anyone else."),
        Part(title: "Camera and photos", body: "The app uses the camera only when you take a photo, and the photo library only when you choose to save a timelapse video. Photos are processed entirely on your device."),
        Part(title: "No tracking", body: "The app has no accounts, advertising, analytics or tracking, and does not connect to the internet."),
        Part(title: "Deleting your data", body: "You can delete a photo or a whole project at any time, or delete everything by deleting the app."),
        Part(title: "Changes", body: "Any updates to this policy will be posted here.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Privacy Policy")
                            .font(.largeTitle.weight(.bold))
                        Text("Last updated November 2026")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("Same Spot does not collect, share or sell any personal information.")

                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.headline)
                            Text(section.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .presentationDragIndicator(.visible)
    }
}
