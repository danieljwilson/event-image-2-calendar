import SwiftUI
import SwiftData

struct EventDetailView: View {
    let eventID: UUID
    let processor: BackgroundEventProcessor

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var icsFileURL: URL?

    @Query private var matchingEvents: [PersistedEvent]

    init(eventID: UUID, processor: BackgroundEventProcessor) {
        self.eventID = eventID
        self.processor = processor
        _matchingEvents = Query(filter: #Predicate<PersistedEvent> { $0.id == eventID })
    }

    private var event: PersistedEvent? { matchingEvents.first }

    var body: some View {
        Group {
            if let event {
                eventContent(event)
            } else {
                ContentUnavailableView("Event Not Found", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = icsFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func eventContent(_ event: PersistedEvent) -> some View {
        Form {
            if let imageData = event.imageData, let uiImage = UIImage(data: imageData) {
                Section {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Section("Event") {
                TextField("Title", text: Binding(
                    get: { event.title },
                    set: { event.title = $0; event.updatedAt = Date() }
                ))
                .font(.headline)
            }

            Section("Date & Time") {
                DatePicker("Start", selection: Binding(
                    get: { event.startDate },
                    set: { event.startDate = $0; event.updatedAt = Date() }
                ))
                DatePicker("End", selection: Binding(
                    get: { event.endDate },
                    set: { event.endDate = $0; event.updatedAt = Date() }
                ))
            }

            Section("Venue") {
                TextField("Venue name", text: Binding(
                    get: { event.venue },
                    set: { event.venue = $0; event.updatedAt = Date() }
                ))
                TextField("Address", text: Binding(
                    get: { event.address },
                    set: { event.address = $0; event.updatedAt = Date() }
                ))
            }

            Section("Description") {
                TextEditor(text: Binding(
                    get: { event.eventDescription },
                    set: { event.eventDescription = $0; event.updatedAt = Date() }
                ))
                .frame(minHeight: 80)
            }

            Section {
                if event.status == .ready || event.status == .added {
                    Button {
                        CalendarService.openGoogleCalendar(event: event.toEventDetails())
                        event.status = .added
                        event.updatedAt = Date()
                    } label: {
                        Label(
                            event.status == .added ? "Open in Google Calendar Again" : "Add to Google Calendar",
                            systemImage: "calendar.badge.plus"
                        )
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Button {
                    let details = event.toEventDetails()
                    if let url = CalendarService.generateICSFile(for: details) {
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

                if event.status == .failed {
                    Button {
                        processor.retryEvent(event, context: modelContext)
                    } label: {
                        Label("Retry Extraction", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if event.status == .ready {
                    Button(role: .destructive) {
                        event.status = .dismissed
                        event.updatedAt = Date()
                        dismiss()
                    } label: {
                        Label("Dismiss Event", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            if event.status == .failed, let error = event.errorMessage {
                Section("Error Details") {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
