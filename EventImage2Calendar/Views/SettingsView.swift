import SwiftUI

struct SettingsView: View {
    @AppStorage("digestEnabled") private var digestEnabled = true
    @AppStorage("digestEmail") private var digestEmail = ""
    @AppStorage("openCameraOnLaunch") private var openCameraOnLaunch = true
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(\.dismiss) private var dismiss
    @State private var emailDraft = ""
    @State private var isSaving = false
    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Daily digest email", isOn: $digestEnabled)
                    TextField("Email address", text: $emailDraft)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($emailFocused)
                        .disabled(!digestEnabled)
                        .foregroundStyle(digestEnabled ? .primary : .secondary)
                        .onSubmit {
                            saveEmail()
                        }

                    if digestEnabled && emailDraft != digestEmail && !emailDraft.isEmpty {
                        Button {
                            saveEmail()
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Save Email")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(isSaving)
                    }
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
                    Button("Show Onboarding") {
                        hasSeenOnboarding = false
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                emailDraft = digestEmail
            }
        }
    }

    private func saveEmail() {
        let email = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return }
        isSaving = true
        emailFocused = false

        Task {
            let success = await WorkerAuthService.updateDigestEmail(email)
            await MainActor.run {
                isSaving = false
                if success {
                    digestEmail = email
                }
            }
        }
    }
}
