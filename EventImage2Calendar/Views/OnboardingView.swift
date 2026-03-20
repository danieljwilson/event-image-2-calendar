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
        imageMaxHeight: 280
    ),
    OnboardingPageData(
        imageName: "Onboarding/OnboardingExtraction",
        title: "AI Magic!",
        description: "Date, time, venue, and description are automatically extracted \u{2014} no typing needed.",
        imageMaxHeight: 260
    ),
    OnboardingPageData(
        imageName: "Onboarding/OnboardingAddCalendar",
        title: "One Tap Add",
        description: "Check the details, make any edits, then tap \u{2018}Add to Google Calendar\u{2019}.",
        imageMaxHeight: 280
    ),
    OnboardingPageData(
        imageName: "Onboarding/OnboardingShare",
        title: "Share From Anywhere",
        description: "See something interesting on Instagram/Facebook or on the web?\nUse the Share button to send event images straight to the app.",
        imageMaxHeight: 320
    ),
]

// Total pages: 4 feature + permissions + digest + final = 7
// Indices:     0-3               4             5        6
private let permissionsPageIndex = featurePages.count
private let digestPageIndex = featurePages.count + 1
private let finalPageIndex = featurePages.count + 2
private let totalPages = featurePages.count + 3

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("digestEnabled") private var digestEnabled = true
    @AppStorage("digestEmail") private var digestEmail = ""
    @State private var currentPage = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $currentPage) {
                ForEach(Array(featurePages.enumerated()), id: \.offset) { index, page in
                    OnboardingFeaturePage(data: page)
                        .tag(index)
                }

                PermissionsPage()
                    .tag(permissionsPageIndex)

                DigestSetupPage(
                    digestEnabled: $digestEnabled,
                    digestEmail: $digestEmail
                )
                .tag(digestPageIndex)

                FinalPage {
                    completeOnboarding()
                }
                .tag(finalPageIndex)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            if currentPage < finalPageIndex {
                Button("Skip") {
                    completeOnboarding()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.trailing, 24)
                .padding(.top, 16)
            }
        }
    }

    private func completeOnboarding() {
        if digestEnabled && !digestEmail.isEmpty {
            let email = digestEmail
            Task {
                await WorkerAuthService.updateDigestEmail(email)
            }
        }
        hasSeenOnboarding = true
    }
}

// MARK: - Feature Page

private struct OnboardingFeaturePage: View {
    let data: OnboardingPageData

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 60)

            Text(data.title)
                .font(.title)
                .fontWeight(.light)
                .multilineTextAlignment(.center)

            Spacer()
                .frame(height: 8)

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

            Spacer()
            Spacer()
                .frame(height: 40)
        }
        .padding()
    }
}

// MARK: - Permissions Page

private struct PermissionsPage: View {
    @State private var cameraGranted = false
    @State private var locationGranted = false
    @StateObject private var locationDelegate = OnboardingLocationDelegate()

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 60)

            Text("Permissions")
                .font(.title)
                .fontWeight(.light)
                .multilineTextAlignment(.center)

            Spacer()
                .frame(height: 8)

            Image("Onboarding/OnboardingPermissionsShield")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 140)

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
                )
                permissionRow(
                    imageName: "Onboarding/OnboardingPermissionsPhotos",
                    title: "Photo Library",
                    detail: "Select poster photos you\u{2019}ve already taken",
                    granted: nil
                )
                permissionRow(
                    imageName: "Onboarding/OnboardingPermissionsLocation",
                    title: "Location",
                    detail: "City-level only \u{2014} improves extraction accuracy",
                    granted: locationGranted
                )
            }
            .padding(.horizontal, 40)

            Button {
                requestPermissions()
            } label: {
                Text("Grant Permissions")
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

    private func permissionRow(imageName: String, title: String, detail: String, granted: Bool?) -> some View {
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
            }

            Spacer()

            if let granted {
                Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(granted ? .green : .secondary)
            }
        }
    }

    private func checkCurrentStatus() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let locStatus = CLLocationManager().authorizationStatus
        locationGranted = locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                cameraGranted = granted
            }
        }

        locationDelegate.requestPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let status = locationDelegate.manager.authorizationStatus
            locationGranted = status == .authorizedWhenInUse || status == .authorizedAlways
        }
    }
}

private class OnboardingLocationDelegate: NSObject, ObservableObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        objectWillChange.send()
    }
}

// MARK: - Digest Setup Page

private struct DigestSetupPage: View {
    @Binding var digestEnabled: Bool
    @Binding var digestEmail: String
    @FocusState private var emailFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 60)

            Text("Daily Digest")
                .font(.title)
                .fontWeight(.light)
                .multilineTextAlignment(.center)

            Spacer()
                .frame(height: 24)

            Image("Onboarding/OnboardingDigestEmail")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 160)

            VStack(spacing: 4) {
                Text("Get a daily email with events you haven\u{2019}t added to your calendar yet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("One click to add from the email.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                TextField("Email address", text: $digestEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                    .focused($emailFocused)
                    .padding(.horizontal, 40)

                Toggle("Enable daily digest", isOn: $digestEnabled)
                    .padding(.horizontal, 40)
            }

            Text("You can always change this later in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
                .frame(height: 40)
        }
        .padding()
    }
}

// MARK: - Final Page

private struct FinalPage: View {
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 60)

            Text("All Set")
                .font(.title)
                .fontWeight(.light)
                .multilineTextAlignment(.center)

            Spacer()
                .frame(height: 8)

            Image("Onboarding/OnboardingAllSet")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 280)
                .padding(.horizontal, 32)

            VStack(spacing: 4) {
                Text("Never miss an event again.")
                Text("Or do.")
                Text("But at least it will be on purpose.")
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

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

            Spacer()
                .frame(height: 40)
        }
        .padding()
    }
}
