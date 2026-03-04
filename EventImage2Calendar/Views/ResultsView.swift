import SwiftUI

struct ResultsView: View {
    @Bindable var extractor: EventExtractor
    var onDismiss: () -> Void

    @State private var showShareSheet = false
    @State private var icsFileURL: URL?

    var body: some View {
        Group {
            if extractor.isLoading {
                loadingView
            } else if let event = extractor.extractedEvent {
                eventForm(event)
            } else if let error = extractor.errorMessage {
                errorView(error)
            } else {
                ProgressView("Starting extraction...")
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("New Scan") {
                    onDismiss()
                }
            }
        }
        .task {
            await extractor.extractEvent()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = icsFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            if let image = extractor.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
            }

            ProgressView()
                .controlSize(.large)

            Text("Extracting event details...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Event form

    private func eventForm(_ event: EventDetails) -> some View {
        Form {
            // Poster thumbnail
            if let image = extractor.capturedImage {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Event details
            Section("Event") {
                TextField("Title", text: Binding(get: { event.title }, set: { event.title = $0 }))
                    .font(.headline)
            }

            Section("Date & Time") {
                DatePicker("Start", selection: Binding(get: { event.startDate }, set: { event.startDate = $0 }))
                DatePicker("End", selection: Binding(get: { event.endDate }, set: { event.endDate = $0 }))
            }

            Section("Venue") {
                TextField("Venue name", text: Binding(get: { event.venue }, set: { event.venue = $0 }))
                TextField("Address", text: Binding(get: { event.address }, set: { event.address = $0 }))
            }

            Section("Description") {
                TextEditor(text: Binding(get: { event.eventDescription }, set: { event.eventDescription = $0 }))
                    .frame(minHeight: 80)
            }

            // Actions
            Section {
                Button {
                    CalendarService.openGoogleCalendar(event: event)
                } label: {
                    Label("Add to Google Calendar", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Button {
                    if let url = CalendarService.generateICSFile(for: event) {
                        icsFileURL = url
                        showShareSheet = true
                    }
                } label: {
                    Label("Export .ics File", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Error

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Extraction Failed")
                .font(.title2.bold())

            Text(error)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                Task { await extractor.extractEvent() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

// MARK: - Share sheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
