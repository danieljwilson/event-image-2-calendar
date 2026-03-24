import SwiftUI
import MessageUI

// MARK: - Settings Form Content (embeddable in tab bar)

struct SettingsFormContent: View {
    @AppStorage("digestEnabled") private var digestEnabled = false
    @AppStorage("digestEmail") private var digestEmail = ""
    @AppStorage("openCameraOnLaunch") private var openCameraOnLaunch = true
    @AppStorage("extractionLanguage") private var extractionLanguage = "English"

    private let languageOptions = [
        "English", "French", "German", "Italian", "Spanish",
        "Portuguese", "Dutch", "Japanese", "Korean", "Chinese"
    ]
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var isSaving = false
    @State private var showEmailPrompt = false
    @State private var emailPromptDraft = ""
    @State private var showFeedbackMail = false
    @State private var showNoMailAlert = false

    var body: some View {
        Form {
            Section {
                Toggle("Daily digest email", isOn: Binding(
                    get: { digestEnabled },
                    set: { newValue in
                        if newValue {
                            if digestEmail.isEmpty {
                                emailPromptDraft = ""
                                showEmailPrompt = true
                            } else {
                                digestEnabled = true
                            }
                        } else {
                            digestEnabled = false
                        }
                    }
                ))
                if digestEnabled && !digestEmail.isEmpty {
                    LabeledContent("Email", value: digestEmail)
                    Button("Change Email") {
                        emailPromptDraft = digestEmail
                        showEmailPrompt = true
                    }
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

            Section {
                Picker("Description language", selection: $extractionLanguage) {
                    ForEach(languageOptions, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("Extraction")
            } footer: {
                Text("Language for event descriptions. Titles and venue names are kept in their original language.")
            }

            Section("Diagnostics") {
                NavigationLink("Share Extension Log") {
                    DebugLogView()
                }
                NavigationLink("Feedback Log") {
                    FeedbackLogView()
                }
            }

            Section("Feedback") {
                Button {
                    if MFMailComposeViewController.canSendMail() {
                        showFeedbackMail = true
                    } else {
                        UIPasteboard.general.string = FeedbackService.feedbackEmail
                        showNoMailAlert = true
                    }
                } label: {
                    Label("Send Feedback", systemImage: "envelope")
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                Button("Show Onboarding") {
                    hasSeenOnboarding = false
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Enter your email", isPresented: $showEmailPrompt) {
            TextField("Email address", text: $emailPromptDraft)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
            Button("Enable") {
                let email = emailPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard isValidEmail(email) else { return }
                isSaving = true
                Task {
                    let success = await WorkerAuthService.updateDigestEmail(email)
                    await MainActor.run {
                        isSaving = false
                        if success {
                            digestEmail = email
                            digestEnabled = true
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter your email to receive daily digest reminders.")
        }
        .sheet(isPresented: $showFeedbackMail) {
            FeedbackMailView(screenshotData: FeedbackService.captureScreenshot()) { didSend, _ in
                if didSend {
                    FeedbackService.logFeedback(messagePreview: "(sent from Settings)", hadScreenshot: true)
                }
            }
        }
        .alert("Mail Not Available", isPresented: $showNoMailAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Mail is not configured on this device. Send feedback to: \(FeedbackService.feedbackEmail)\n\nThe address has been copied to your clipboard.")
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.firstIndex(of: "@") else { return false }
        let afterAt = trimmed[trimmed.index(after: atIndex)...]
        return !afterAt.isEmpty && afterAt.contains(".")
    }
}

// MARK: - Settings View (standalone sheet wrapper)

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsFormContent()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Debug Log Viewer

struct DebugLogView: View {
    @State private var logContent: String = ""

    var body: some View {
        ScrollView {
            if logContent.isEmpty {
                ContentUnavailableView("No Log Data", systemImage: "doc.text", description: Text("Share from another app to generate log entries"))
            } else {
                Text(logContent)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Debug Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = logContent
                    } label: {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    }
                    .disabled(logContent.isEmpty)

                    Button(role: .destructive) {
                        SharedContainerService.clearDebugLog()
                        logContent = ""
                    } label: {
                        Label("Clear Log", systemImage: "trash")
                    }
                    .disabled(logContent.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            logContent = SharedContainerService.readDebugLog() ?? ""
        }
    }
}

// MARK: - Feedback Log Viewer

struct FeedbackLogView: View {
    @State private var entries: [FeedbackLogEntry] = []

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("No Feedback Sent", systemImage: "envelope", description: Text("Feedback you send will be logged here"))
            } else {
                ForEach(entries.reversed(), id: \.timestamp) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.timestamp, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("v\(entry.appVersion) (\(entry.buildNumber)) - \(entry.deviceModel)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if !entry.messagePreview.isEmpty {
                            Text(entry.messagePreview)
                                .font(.subheadline)
                                .lineLimit(3)
                        }
                        if entry.hadScreenshot {
                            Label("Screenshot attached", systemImage: "camera")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Feedback Log")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            entries = FeedbackService.readFeedbackLog()
        }
    }
}
