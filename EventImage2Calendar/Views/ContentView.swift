import SwiftUI
import UIKit

@Observable
class EventExtractor {
    var capturedImage: UIImage?
    var extractedEvent: EventDetails?
    var isLoading = false
    var errorMessage: String?

    let locationService = LocationService()

    func extractEvent() async {
        guard let image = capturedImage,
              let imageData = image.resizedForAPI() else {
            errorMessage = "Failed to process the image."
            return
        }

        isLoading = true
        errorMessage = nil
        extractedEvent = nil

        do {
            let event = try await ClaudeAPIService.extractEvent(
                imageData: imageData,
                location: locationService.currentLocation
            )
            extractedEvent = event
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reset() {
        capturedImage = nil
        extractedEvent = nil
        isLoading = false
        errorMessage = nil
    }
}

struct ContentView: View {
    @State private var extractor = EventExtractor()
    @State private var showResults = false

    var body: some View {
        NavigationStack {
            CameraView { image in
                extractor.capturedImage = image
                showResults = true
            }
            .navigationDestination(isPresented: $showResults) {
                ResultsView(extractor: extractor) {
                    showResults = false
                    extractor.reset()
                }
            }
        }
        .onAppear {
            extractor.locationService.requestLocation()
        }
    }
}
