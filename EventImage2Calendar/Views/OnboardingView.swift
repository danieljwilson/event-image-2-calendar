import SwiftUI
import AVFoundation
import CoreLocation

private struct OnboardingPageData {
    let symbol: String
    let title: String
    let description: String
    let color: Color
}

private let featurePages: [OnboardingPageData] = [
    OnboardingPageData(
        symbol: "camera.viewfinder",
        title: "Snap a Poster",
        description: "See a poster for an interesting event? Just take a photo.",
        color: .blue
    ),
    OnboardingPageData(
        symbol: "sparkles",
        title: "Event Snap Does the Rest",
        description: "Date, time, venue, and description are automatically extracted \u{2014} no typing needed.",
        color: .purple
    ),
    OnboardingPageData(
        symbol: "calendar.badge.plus",
        title: "One Click to Add to Calendar",
        description: "Check the details, make any edits, then tap \u{2018}Add to Google Calendar\u{2019}.",
        color: .orange
    ),
    OnboardingPageData(
        symbol: "square.and.arrow.up",
        title: "Share From Anywhere",
        description: "See something interesting on Instagram/Facebook or on the web? Use the Share button to send event images straight to the app.",
        color: .green
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
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: data.symbol)
                .font(.system(size: 80))
                .foregroundStyle(data.color)
                .symbolEffect(.bounce, value: appeared)

            Text(data.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)

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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appeared = true
            }
        }
    }
}

// MARK: - Permissions Page

private struct PermissionsPage: View {
    @State private var appeared = false
    @State private var cameraGranted = false
    @State private var locationGranted = false
    @StateObject private var locationDelegate = OnboardingLocationDelegate()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 80))
                .foregroundStyle(.teal)
                .symbolEffect(.bounce, value: appeared)

            Text("Permissions")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("Event Snap needs a few permissions to work. You can change these anytime in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 16) {
                permissionRow(
                    symbol: "camera.fill",
                    title: "Camera",
                    detail: "Photograph event posters",
                    granted: cameraGranted
                )
                permissionRow(
                    symbol: "photo.on.rectangle",
                    title: "Photo Library",
                    detail: "Select poster photos you\u{2019}ve already taken",
                    granted: nil
                )
                permissionRow(
                    symbol: "location.fill",
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
            .controlSize(.large)
            .padding(.horizontal, 40)

            Spacer()
                .frame(height: 40)
        }
        .padding()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appeared = true
            }
            checkCurrentStatus()
        }
    }

    private func permissionRow(symbol: String, title: String, detail: String, granted: Bool?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.teal)
                .frame(width: 28)

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
    @State private var appeared = false
    @FocusState private var emailFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.badge")
                .font(.system(size: 80))
                .foregroundStyle(.indigo)
                .symbolEffect(.bounce, value: appeared)

            Text("Daily Digest")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("Get a daily email with events you haven\u{2019}t added to your calendar yet. One click to add from the email.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appeared = true
            }
        }
    }
}

// MARK: - Final Page

private struct FinalPage: View {
    let onGetStarted: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "party.popper")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
                .symbolEffect(.bounce, value: appeared)

            Text("You\u{2019}re All Set")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("Never miss an event again. Or do. But at least it will be on purpose.")
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
            .controlSize(.large)
            .padding(.horizontal, 40)

            Spacer()
                .frame(height: 40)
        }
        .padding()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appeared = true
            }
        }
    }
}
