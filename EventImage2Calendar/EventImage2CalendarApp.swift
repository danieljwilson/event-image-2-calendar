import SwiftUI
import SwiftData

@main
struct EventImage2CalendarApp: App {
    init() {
        UserDefaults.standard.register(defaults: [
            "digestEnabled": true,
            "openCameraOnLaunch": true,
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: PersistedEvent.self)
    }
}
