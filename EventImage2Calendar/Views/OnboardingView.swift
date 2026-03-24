import SwiftUI
import AVFoundation
import CoreLocation

private struct OnboardingPageData {
    let imageName: String
    let title: String
    let description: String
    let imageMaxHeight: CGFloat
}

private let featurePages: [OnboardingPageData] = [
    OnboardingPageData(
        imageName: "Onboarding/OnboardingSnapPoster",
        title: "Snap a Poster",
        description: "See a poster for an interesting event? Just take a photo.",
        imageMaxHeight: 220
    ),
    OnboardingPageData(
        imageName: "Onboarding/OnboardingExtraction",
        title: "AI Magic!",
        description: "Date, time, venue, and description are extracted automatically \u{2014} no typing needed.",
        imageMaxHeight: 200
    ),
    OnboardingPageData(
        imageName: "Onboarding/OnboardingAddCalendar",
        title: "One Tap Add",
        description: "Check the details, make any edits, then add to Google Calendar.",
        imageMaxHeight: 220
    ),
    OnboardingPageData(
        imageName: "Onboarding/OnboardingShare",
        title: "Share From Anywhere",
        description: "See an interesting event on social media or the web?\n\nUse the Share button to send event images straight to the app.",
        imageMaxHeight: 320
    ),
]

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("digestEnabled") private var digestEnabled = false
    @AppStorage("digestEmail") private var digestEmail = ""
    @State private var currentPage = 0
    @State private var digestToggleOn = false

    // Dynamic page indexing: beta pages are inserted for TestFlight builds
    private var hasBetaPages: Bool { FeedbackService.isTestFlight }
    private var betaPageCount: Int { hasBetaPages ? 1 : 0 }
    private var featureStartIndex: Int { betaPageCount }
    private var permissionsPageIndex: Int { betaPageCount + featurePages.count }
    private var digestPageIndex: Int { permissionsPageIndex + 1 }
    private var allSetPageIndex: Int { digestPageIndex + 1 }
    private var errorFeedbackPageIndex: Int { allSetPageIndex + 1 } // TestFlight only
    private var thankYouPageIndex: Int { errorFeedbackPageIndex + 1 } // TestFlight only
    private var finalPageIndex: Int { hasBetaPages ? thankYouPageIndex : allSetPageIndex }
    private var totalPages: Int { finalPageIndex + 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ProgressView(value: Double(currentPage + 1), total: Double(totalPages))
                    .tint(.black)
                    .animation(.easeInOut(duration: 0.3), value: currentPage)

                if currentPage < finalPageIndex {
                    Button("Skip") {
                        completeOnboarding()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 4)

            TabView(selection: $currentPage) {
                if hasBetaPages {
                    BetaWelcomePage()
                        .tag(0)
                }

                ForEach(Array(featurePages.enumerated()), id: \.offset) { index, page in
                    OnboardingFeaturePage(data: page)
                        .tag(featureStartIndex + index)
                }

                PermissionsPage {
                    withAnimation { currentPage = min(currentPage + 1, finalPageIndex) }
                }
                .tag(permissionsPageIndex)

                DigestSetupPage(
                    digestEmail: $digestEmail,
                    digestToggleOn: $digestToggleOn
                )
                .tag(digestPageIndex)

                AllSetPage(showGetStarted: !hasBetaPages) {
                    completeOnboarding()
                }
                .tag(allSetPageIndex)

                if hasBetaPages {
                    ErrorFeedbackPage()
                        .tag(errorFeedbackPageIndex)

                    ThankYouPage {
                        completeOnboarding()
                    }
                    .tag(thankYouPageIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .overlay {
                NavigationChevronOverlay(
                    showBack: currentPage > 0,
                    showForward: currentPage < finalPageIndex,
                    onBack: { withAnimation { currentPage = max(currentPage - 1, 0) } },
                    onForward: { withAnimation { currentPage = min(currentPage + 1, finalPageIndex) } }
                )
            }
            .onChange(of: currentPage) { _, _ in
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
        }
    }

    private func completeOnboarding() {
        let email = digestEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if digestToggleOn, !email.isEmpty, email.contains("@"), email.split(separator: "@").last?.contains(".") == true {
            digestEnabled = true
            Task {
                await WorkerAuthService.updateDigestEmail(email)
            }
        } else {
            digestEnabled = false
        }
        hasSeenOnboarding = true
    }
}

// MARK: - Navigation Chevron Overlay

private struct NavigationChevronOverlay: View {
    let showBack: Bool
    let showForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack {
            if showBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.compact.left")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(.leading, 4)
            }

            Spacer()

            if showForward {
                Button(action: onForward) {
                    Image(systemName: "chevron.compact.right")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(.trailing, 4)
            }
        }
    }
}

// MARK: - Beta Badge

private struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.secondary.opacity(0.5)))
    }
}

// MARK: - Beta Welcome Page

private struct BetaWelcomePage: View {
    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Image("Onboarding/OnboardingBetaWelcome")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)

                VStack(spacing: 8) {
                    Text("Thanks for helping test Event Snap.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("We\u{2019}d love your feedback on:")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    feedbackItem("Does extraction work for your local events?")
                    feedbackItem("Is the Share Extension reliable from different apps?")
                    feedbackItem("Any confusing moments in the UI?")
                }
                .padding(.horizontal, 40)
            }

            VStack {
                BetaBadge()
                Text("Welcome, Beta Tester!")
                    .font(.title)
                    .fontWeight(.light)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                Spacer()
            }
            .padding(.top, 60)
        }
        .padding()
    }

    private func feedbackItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
                .padding(.top, 7)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Feature Page

private struct OnboardingFeaturePage: View {
    let data: OnboardingPageData

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Image(data.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: data.imageMaxHeight)
                    .padding(.horizontal, 32)

                Text(data.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack {
                Text(data.title)
                    .font(.title)
                    .fontWeight(.light)
                    .multilineTextAlignment(.center)
                    .padding(.top, 60)
                Spacer()
            }
        }
        .padding()
    }
}

// MARK: - Permissions Page

private struct PermissionsPage: View {
    @State private var cameraGranted = false
    @StateObject private var locationDelegate = OnboardingLocationDelegate()
    let onAdvance: () -> Void

    private var allGranted: Bool {
        cameraGranted && locationDelegate.isAuthorized
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Permissions")
                .font(.title)
                .fontWeight(.light)
                .multilineTextAlignment(.center)

            Spacer()
                .frame(height: 12)

            Image("Onboarding/OnboardingPermissionsShield")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 140)

            Spacer()
                .frame(height: 12)

            VStack(spacing: 4) {
                Text("We need a few permissions to work.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("You can change these anytime in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 16) {
                permissionRow(
                    imageName: "Onboarding/OnboardingPermissionsCamera",
                    title: "Camera",
                    detail: "Photograph event posters",
                    granted: cameraGranted
                ) { requestCamera() }
                permissionRow(
                    imageName: "Onboarding/OnboardingPermissionsLocation",
                    title: "Location",
                    detail: "City-level only \u{2014} improves extraction accuracy",
                    granted: locationDelegate.isAuthorized
                ) { requestLocation() }
            }
            .padding(.horizontal, 40)

            Spacer()

            Button {
                if allGranted {
                    onAdvance()
                } else {
                    requestPermissions()
                }
            } label: {
                Text(allGranted ? "Continue" : "Grant Permissions")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)
            .controlSize(.large)
            .padding(.horizontal, 40)

            Spacer()
                .frame(height: 40)
        }
        .padding()
        .onAppear {
            checkCurrentStatus()
        }
    }

    private func permissionRow(imageName: String, title: String, detail: String, granted: Bool?, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if let granted {
                    Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(granted ? .green : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func checkCurrentStatus() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    private func requestCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { cameraGranted = granted }
            }
        } else if status == .denied || status == .restricted {
            openSettings()
        }
    }

    private func requestLocation() {
        let status = locationDelegate.manager.authorizationStatus
        if status == .notDetermined {
            locationDelegate.requestPermission()
        } else if status == .denied || status == .restricted {
            openSettings()
        }
    }

    private func requestPermissions() {
        requestCamera()
        requestLocation()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private class OnboardingLocationDelegate: NSObject, ObservableObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    @Published var isAuthorized: Bool = false

    override init() {
        super.init()
        manager.delegate = self
        let status = manager.authorizationStatus
        isAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        isAuthorized = manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
    }
}

// MARK: - Digest Setup Page

private struct DigestSetupPage: View {
    @Binding var digestEmail: String
    @Binding var digestToggleOn: Bool
    @State private var showEmailPrompt = false
    @State private var emailPromptDraft = ""

    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.firstIndex(of: "@") else { return false }
        let afterAt = trimmed[trimmed.index(after: atIndex)...]
        return !afterAt.isEmpty && afterAt.contains(".")
    }

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Image("Onboarding/OnboardingDigestEmail")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)

                VStack(spacing: 8) {
                    Text("Get a daily email with events you haven\u{2019}t yet added to your calendar.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("One click to add from the email.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                VStack(spacing: 8) {
                    Toggle("Enable", isOn: Binding(
                        get: { digestToggleOn },
                        set: { newValue in
                            if newValue {
                                if digestEmail.isEmpty {
                                    emailPromptDraft = ""
                                    showEmailPrompt = true
                                } else {
                                    digestToggleOn = true
                                }
                            } else {
                                digestToggleOn = false
                            }
                        }
                    ))
                    .padding(.horizontal, 40)

                    if digestToggleOn, !digestEmail.isEmpty {
                        LabeledContent("Email", value: digestEmail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 40)
                    }
                }

                Text("You can always change this later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            VStack {
                Text("Daily Digest")
                    .font(.title)
                    .fontWeight(.light)
                    .multilineTextAlignment(.center)
                    .padding(.top, 60)
                Spacer()
            }
        }
        .padding()
        .alert("Enter your email", isPresented: $showEmailPrompt) {
            TextField("Email address", text: $emailPromptDraft)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
            Button("Enable") {
                let email = emailPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard isValidEmail(email) else { return }
                digestEmail = email
                digestToggleOn = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter your email to receive daily digest reminders.")
        }
    }
}

// MARK: - Error Feedback Page (TestFlight only)

private struct ErrorFeedbackPage: View {
    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Image("Onboarding/OnboardingErrorFeedback")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)

                VStack(spacing: 8) {
                    Text("Take a screenshot and we\u{2019}ll ask if you want to send feedback.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Or tap Send Feedback in Settings anytime.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }

            VStack {
                BetaBadge()
                Text("Spotted something off?")
                    .font(.title)
                    .fontWeight(.light)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                Spacer()
            }
            .padding(.top, 60)
        }
        .padding()
    }
}

// MARK: - Thank You Page (TestFlight only)

private struct ThankYouPage: View {
    let onGetStarted: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Image("Onboarding/OnboardingThanks")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)

                Text("We appreciate your help.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack {
                BetaBadge()
                Text("Thank You!")
                    .font(.title)
                    .fontWeight(.light)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                Spacer()
            }
            .padding(.top, 60)

            VStack {
                Spacer()
                Button {
                    onGetStarted()
                } label: {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)
                .controlSize(.large)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .padding()
    }
}

// MARK: - All Set Page

private struct AllSetPage: View {
    var showGetStarted: Bool
    let onGetStarted: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Image("Onboarding/OnboardingAllSet")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .padding(.horizontal, 32)

                VStack(spacing: 16) {
                    Text("Never miss an event again.")
                    Text("Or do. But at least it will be on purpose.")
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }

            VStack {
                Text("All Set")
                    .font(.title)
                    .fontWeight(.light)
                    .multilineTextAlignment(.center)
                    .padding(.top, 60)
                Spacer()
            }

            if showGetStarted {
                VStack {
                    Spacer()
                    Button {
                        onGetStarted()
                    } label: {
                        Text("Get Started")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)
                    .controlSize(.large)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            }
        }
        .padding()
    }
}

// MARK: - Previews

#Preview("Full Flow") {
    OnboardingView()
}

#Preview("Snap a Poster") {
    OnboardingFeaturePage(data: featurePages[0])
}

#Preview("AI Magic") {
    OnboardingFeaturePage(data: featurePages[1])
}

#Preview("One Tap Add") {
    OnboardingFeaturePage(data: featurePages[2])
}

#Preview("Share From Anywhere") {
    OnboardingFeaturePage(data: featurePages[3])
}

#Preview("Permissions") {
    PermissionsPage { }
}

#Preview("Digest Setup") {
    DigestSetupPage(
        digestEmail: .constant(""),
        digestToggleOn: .constant(false)
    )
}

#Preview("Beta Welcome") {
    BetaWelcomePage()
}

#Preview("Error Feedback") {
    ErrorFeedbackPage()
}

#Preview("Thank You") {
    ThankYouPage { }
}

#Preview("All Set") {
    AllSetPage(showGetStarted: true) { }
}
