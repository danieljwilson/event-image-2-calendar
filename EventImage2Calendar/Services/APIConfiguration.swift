import Foundation

enum APIConfiguration {
    static var workerBaseURL: URL {
        #if DEBUG
        URL(string: "https://event-digest-worker-staging.daniel-j-wilson-587.workers.dev")!
        #else
        URL(string: "https://event-digest-worker.daniel-j-wilson-587.workers.dev")!
        #endif
    }
}
