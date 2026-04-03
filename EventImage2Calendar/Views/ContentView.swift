import SwiftUI

struct ContentView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    private var shouldSkipOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("--skip-onboarding")
    }

    var body: some View {
        if hasSeenOnboarding || shouldSkipOnboarding {
            EventListView()
        } else {
            OnboardingView()
        }
    }
}
