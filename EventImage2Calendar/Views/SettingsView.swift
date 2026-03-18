import SwiftUI

struct SettingsView: View {
    @AppStorage("digestEnabled") private var digestEnabled = true
    @AppStorage("openCameraOnLaunch") private var openCameraOnLaunch = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Daily digest email", isOn: $digestEnabled)
                } header: {
                    Text("Daily Digest")
                } footer: {
                    Text("Receive a daily email reminder of events you haven't added to your calendar yet.")
                }

                Section {
                    Toggle("Open camera on launch", isOn: $openCameraOnLaunch)
                } header: {
                    Text("Camera")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
