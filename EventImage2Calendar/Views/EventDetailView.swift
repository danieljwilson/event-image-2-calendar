import SwiftUI
import SwiftData

enum MultiDayMode: String, CaseIterable {
    case selectDays = "Select Days"
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
    @State private var selectedDateIndices: Set<Int> = []
    @State private var didInitSelection = false

    @Query private var matchingEvents: [PersistedEvent]

    init(eventID: UUID, processor: BackgroundEventProcessor) {
        self.eventID = eventID
        self.processor = processor
        _matchingEvents = Query(filter: #Predicate<PersistedEvent> { $0.id == eventID })
    }

    private var event: PersistedEvent? { matchingEvents.first }

    private var isMultiDay: Bool {
        guard let event else { return false }
        return event.eventDates.count > 1
    }

    private var eventCount: Int {
        if isMultiDay && multiDayMode == .selectDays {
            return selectedDateIndices.count
        }
        return 1
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

            if event.status == .failed && (event.needsDateCorrection || event.isPastEvent) {
                Section {
                    Button {
                        event.hasExplicitDate = true
                        event.hasExplicitTime = true
                        event.status = .ready
                        event.errorMessage = nil
                        event.updatedAt = Date()
                        event.googleCalendarURL = CalendarService.googleCalendarURL(
                            for: event.toEventDetails()
                        )?.absoluteString
                    } label: {
                        let label = event.isPastEvent ? "Confirm Updated Date" :
                            "Confirm \(event.hasExplicitDate ? "Time" : (event.hasExplicitTime ? "Date" : "Date & Time"))"
                        Label(label, systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    Button(role: .destructive) {
                        DigestService.dequeueEvent(event, context: modelContext)
                        modelContext.delete(event)
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

            Section {
                if event.status == .ready || event.status == .added {
                    Button {
                        let details = buildEventDetails(from: event)
                        CalendarService.openGoogleCalendar(events: details)
                        DigestService.acceptEvent(
                            event,
                            googleCalendarURL: digestGoogleCalendarURL(for: details),
                            context: modelContext
                        )
                    } label: {
                        Label(
                            eventCount > 1 ? "Add \(eventCount) Events to Google Calendar" :
                                (event.status == .added ? "Open in Google Calendar" : "Add to Google Calendar"),
                            systemImage: "calendar.badge.plus"
                        )
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .disabled(isMultiDay && multiDayMode == .selectDays && selectedDateIndices.isEmpty)
                }

                if isMultiDay && multiDayMode == .selectDays && selectedDateIndices.count >= 5 {
                    Text("Tip: Use \"Export .ics\" below to add all \(selectedDateIndices.count) events in one step.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                if event.status == .ready || event.status == .added {
                    Button {
                        let details = buildEventDetails(from: event)
                        if let url = CalendarService.generateICSFile(for: details) {
                            icsFileURL = url
                            showShareSheet = true
                            DigestService.acceptEvent(
                                event,
                                googleCalendarURL: digestGoogleCalendarURL(for: details),
                                context: modelContext
                            )
                        }
                    } label: {
                        Label(
                            eventCount > 1 ? "Export \(eventCount) Events as .ics" : "Export .ics File",
                            systemImage: "square.and.arrow.up"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .disabled(isMultiDay && multiDayMode == .selectDays && selectedDateIndices.isEmpty)
                }

                if event.status == .failed && event.hasExplicitDate {
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
                        DigestService.dequeueEvent(event, context: modelContext)
                        modelContext.delete(event)
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
                        .foregroundStyle(event.hasExplicitDate ? .red : .orange)
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

                if multiDayMode == .selectDays {
                    let dates = parsedEventDates(event)
                    if !dates.isEmpty {
                        Button {
                            if selectedDateIndices.count == dates.count {
                                selectedDateIndices.removeAll()
                            } else {
                                selectedDateIndices = Set(0..<dates.count)
                            }
                        } label: {
                            Text(selectedDateIndices.count == dates.count ? "Deselect All" : "Select All")
                                .font(.caption)
                        }

                        ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                            Button {
                                if selectedDateIndices.contains(index) {
                                    selectedDateIndices.remove(index)
                                } else {
                                    selectedDateIndices.insert(index)
                                }
                            } label: {
                                HStack {
                                    if event.isAllDay {
                                        Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                            .foregroundStyle(.primary)
                                    } else {
                                        Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                                            .foregroundStyle(.primary)
                                    }
                                    Spacer()
                                    if selectedDateIndices.contains(index) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    let dates = parsedEventDates(event)
                    let spanStart = dates.min() ?? event.startDate
                    let spanEnd = dates.max() ?? event.endDate
                    HStack {
                        Text("Start")
                        Spacer()
                        Text(spanStart.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("End")
                        Spacer()
                        Text(spanEnd.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .foregroundStyle(.secondary)
                    }
                    Text("Creates an all-day event spanning the full date range.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                if !didInitSelection {
                    let count = event.eventDates.count
                    selectedDateIndices = Set(0..<count)
                    didInitSelection = true
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
        let tz = event.timezone.flatMap { TimeZone(identifier: $0) } ?? .current

        let datetimeFormatter = DateFormatter()
        datetimeFormatter.locale = Locale(identifier: "en_US_POSIX")
        datetimeFormatter.timeZone = tz

        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = tz

        let datetimeFormats = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"]

        return event.eventDates.compactMap { dateString in
            for format in datetimeFormats {
                datetimeFormatter.dateFormat = format
                if let date = datetimeFormatter.date(from: dateString) { return date }
            }
            return dateOnlyFormatter.date(from: dateString)
        }
    }

    private func buildEventDetails(from event: PersistedEvent) -> [EventDetails] {
        if isMultiDay && multiDayMode == .selectDays {
            let dates = parsedEventDates(event)
            let duration = event.endDate.timeIntervalSince(event.startDate)

            return selectedDateIndices.sorted().compactMap { index -> EventDetails? in
                guard index < dates.count else { return nil }
                let start = dates[index]
                let end = event.isAllDay ? start : start.addingTimeInterval(duration)
                return EventDetails(
                    title: event.title,
                    startDate: start,
                    endDate: end,
                    venue: event.venue,
                    address: event.address,
                    eventDescription: event.eventDescription,
                    timezone: event.timezone,
                    isAllDay: event.isAllDay
                )
            }
        } else if isMultiDay {
            // Full Event mode: create all-day spanning event from eventDates range
            let dates = parsedEventDates(event)
            guard let earliest = dates.min(), let latest = dates.max() else {
                return [event.toEventDetails()]
            }
            let cal = Calendar.current
            let spanStart = cal.startOfDay(for: earliest)
            let spanEnd = cal.startOfDay(for: latest)
            return [EventDetails(
                title: event.title,
                startDate: spanStart,
                endDate: spanEnd,
                venue: event.venue,
                address: event.address,
                eventDescription: event.eventDescription,
                timezone: event.timezone,
                isAllDay: true
            )]
        } else {
            return [event.toEventDetails()]
        }
    }

    private func digestGoogleCalendarURL(for details: [EventDetails]) -> String? {
        guard details.count == 1, let event = details.first else { return nil }
        return CalendarService.googleCalendarURL(for: event)?.absoluteString
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
