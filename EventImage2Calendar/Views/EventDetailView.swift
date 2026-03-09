import SwiftUI
import SwiftData

enum MultiDayMode: String, CaseIterable {
    case singleDay = "Single Day"
    case fullEvent = "Full Event"
}

struct EventDetailView: View {
    let eventID: UUID
    let processor: BackgroundEventProcessor

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var icsFileURL: URL?
    @State private var multiDayMode: MultiDayMode = .fullEvent
    @State private var selectedDateIndex: Int = 0

    @Query private var matchingEvents: [PersistedEvent]

    init(eventID: UUID, processor: BackgroundEventProcessor) {
        self.eventID = eventID
        self.processor = processor
        _matchingEvents = Query(filter: #Predicate<PersistedEvent> { $0.id == eventID })
    }

    private var event: PersistedEvent? { matchingEvents.first }

    private var isMultiDay: Bool {
        guard let event else { return false }
        return event.isAllDay && event.eventDates.count > 1
    }

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
            if event.status == .processing {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Extracting event details...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }
            }

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

            dateSection(event)

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
                        let details = buildEventDetails(from: event)
                        CalendarService.openGoogleCalendar(event: details)
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
                    let details = buildEventDetails(from: event)
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
                    if event.canRetry {
                        Button {
                            processor.retryEvent(event, context: modelContext)
                        } label: {
                            Label(
                                "Retry Extraction (\(event.retryCount)/\(PersistedEvent.maxRetryCount))",
                                systemImage: "arrow.clockwise"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } else {
                        Text("Maximum retries reached (\(PersistedEvent.maxRetryCount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
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

    // MARK: - Date Section

    @ViewBuilder
    private func dateSection(_ event: PersistedEvent) -> some View {
        if isMultiDay {
            Section("Date") {
                Picker("Mode", selection: $multiDayMode) {
                    ForEach(MultiDayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if multiDayMode == .singleDay {
                    let dates = parsedEventDates(event)
                    if !dates.isEmpty {
                        Picker("Date", selection: $selectedDateIndex) {
                            ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                                Text(date, style: .date).tag(index)
                            }
                        }
                    }
                } else {
                    HStack {
                        Text("Start")
                        Spacer()
                        Text(event.startDate, style: .date)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("End")
                        Spacer()
                        Text(event.endDate, style: .date)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Section("Date & Time") {
                Toggle("All Day", isOn: Binding(
                    get: { event.isAllDay },
                    set: { event.isAllDay = $0; event.updatedAt = Date() }
                ))

                if event.isAllDay {
                    DatePicker("Start", selection: Binding(
                        get: { event.startDate },
                        set: { event.startDate = $0; event.updatedAt = Date() }
                    ), displayedComponents: .date)
                    DatePicker("End", selection: Binding(
                        get: { event.endDate },
                        set: { event.endDate = $0; event.updatedAt = Date() }
                    ), displayedComponents: .date)
                } else {
                    DatePicker("Start", selection: Binding(
                        get: { event.startDate },
                        set: { event.startDate = $0; event.updatedAt = Date() }
                    ))
                    DatePicker("End", selection: Binding(
                        get: { event.endDate },
                        set: { event.endDate = $0; event.updatedAt = Date() }
                    ))
                }
            }
        }
    }

    // MARK: - Helpers

    private func parsedEventDates(_ event: PersistedEvent) -> [Date] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let tz = event.timezone { formatter.timeZone = TimeZone(identifier: tz) }

        return event.eventDates.compactMap { formatter.date(from: $0) }
    }

    private func buildEventDetails(from event: PersistedEvent) -> EventDetails {
        if isMultiDay && multiDayMode == .singleDay {
            let dates = parsedEventDates(event)
            let safeIndex = min(selectedDateIndex, dates.count - 1)
            let selectedDate = dates.isEmpty ? event.startDate : dates[max(0, safeIndex)]

            return EventDetails(
                title: event.title,
                startDate: selectedDate,
                endDate: selectedDate,
                venue: event.venue,
                address: event.address,
                eventDescription: event.eventDescription,
                timezone: event.timezone,
                isAllDay: true
            )
        } else {
            return event.toEventDetails()
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
