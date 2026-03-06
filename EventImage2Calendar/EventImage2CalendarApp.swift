import SwiftUI
import SwiftData

@main
struct EventImage2CalendarApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: PersistedEvent.self)
    }
}
