import SwiftUI

/// The layout shared by How to Use, About and Privacy Policy: a title, a line under it,
/// an opening paragraph, then short headed sections and a Done button.
struct InfoPart: Identifiable {
    let title: String
    let text: String
    var id: String { title }
}

struct InfoSheet<Extra: View>: View {
    let title: String
    let subtitle: String
    let intro: String
    let parts: [InfoPart]
    @ViewBuilder var extra: () -> Extra

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.largeTitle.weight(.bold))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(intro)

                    ForEach(parts) { part in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(part.title)
                                .font(.headline)
                            Text(part.text)
                                .foregroundStyle(.secondary)
                        }
                    }

                    extra()
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

extension InfoSheet where Extra == EmptyView {
    init(title: String, subtitle: String, intro: String, parts: [InfoPart]) {
        self.init(title: title, subtitle: subtitle, intro: intro, parts: parts) { EmptyView() }
    }
}

/// Same words as PRIVACY.md, which is the policy link on the App Store page.
struct PrivacyPolicyView: View {
    var body: some View {
        InfoSheet(
            title: "Privacy Policy",
            subtitle: "Last updated November 2026",
            intro: "Same Spot does not collect, share or sell any personal information.",
            parts: [
                InfoPart(title: "Your data", text: "Everything you add, including photos, projects and reminders, is stored only on your device. It is never sent to us or to anyone else."),
                InfoPart(title: "Camera and photos", text: "The app uses the camera only when you take a photo, and the photo library only when you choose to save a timelapse video. Photos are processed entirely on your device."),
                InfoPart(title: "No tracking", text: "The app has no accounts, advertising, analytics or tracking, and does not connect to the internet."),
                InfoPart(title: "Deleting your data", text: "You can delete a photo or a whole project at any time, or delete everything by deleting the app."),
                InfoPart(title: "Changes", text: "Any updates to this policy will be posted here.")
            ]
        )
    }
}

struct HowToUseView: View {
    var body: some View {
        InfoSheet(
            title: "How to Use",
            subtitle: "Same spot, every time",
            intro: "Same Spot keeps every photo lined up with the one before, so they play back as one smooth video.",
            parts: [
                InfoPart(title: "1. Make a project", text: "On Projects, tap + and name the spot. Pick reminder times if you want a nudge."),
                InfoPart(title: "2. Take the original", text: "Stand where you'll stand every time and take the first photo. Use Photo saves it."),
                InfoPart(title: "3. Line up and shoot", text: "Come back, open the Camera, and match the faint photo over the live view. Drag the slider to make it stronger or fainter."),
                InfoPart(title: "Timelapse", text: "The default. The camera always lines up with the original, so the view stays put while the scene changes over days or seasons."),
                InfoPart(title: "Stop Motion", text: "Turn on Stop Motion on the project's page. The camera lines up with your last photo instead, so you can move things a little between each shot."),
                InfoPart(title: "4. Make the video", text: "Open the project and tap Make Timelapse. Pick a speed, then save it to Photos or share it."),
                InfoPart(title: "5. Keep going", text: "Every new photo joins the project. Make the video again whenever you like.")
            ]
        )
    }
}

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        InfoSheet(
            title: "About Same Spot",
            subtitle: "Version \(version)",
            intro: "I wanted a timelapse of my backyard changing through the seasons, but I couldn't frame the photo the same way twice. So I made this.",
            parts: []
        ) {
            if let site = URL(string: "https://katsuma.ca") {
                Link(destination: site) {
                    Label("katsuma.ca", systemImage: "globe")
                        .font(.headline)
                }
            }
        }
    }
}
