import SwiftUI
import SwiftData
import MessageUI

struct EventListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \PersistedEvent.createdAt, order: .reverse) private var events: [PersistedEvent]
    @State private var processor = BackgroundEventProcessor()
    @AppStorage("openCameraOnLaunch") private var openCameraOnLaunch = true
    @State private var showCamera = false
    @State private var hasAppeared = false
    @State private var showLibrary = false
    @State private var selectedTab: Tab = .pending
    @State private var slideDirection: Edge = .trailing
    @State private var correctionEvent: PersistedEvent?
    @State private var expandedMonths: Set<String> = []
    @State private var showFeedbackPrompt = false
    @State private var showFeedbackSheet = false
    @State private var screenshotData: Data?

    enum Tab: String, CaseIterable {
        case pending = "Pending"
        case saved = "Saved"
        case settings = "Settings"
    }

    private var pendingEvents: [PersistedEvent] {
        events.filter { $0.status == .processing || $0.status == .ready || $0.status == .failed }
            .sorted { a, b in
                if a.status == .processing && b.status != .processing { return true }
                if a.status != .processing && b.status == .processing { return false }
                return a.startDate < b.startDate
            }
    }

    private var processedEvents: [PersistedEvent] {
        events.filter { $0.status == .added }
            .sorted { $0.startDate < $1.startDate }
    }

    private var upcomingProcessed: [PersistedEvent] {
        Array(processedEvents.prefix(3))
    }

    private var remainingByMonth: [(key: String, label: String, events: [PersistedEvent])] {
        let remaining = Array(processedEvents.dropFirst(3))
        guard !remaining.isEmpty else { return [] }

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        let keyFormatter = DateFormatter()
        keyFormatter.dateFormat = "yyyy-MM"

        var grouped: [String: (label: String, events: [PersistedEvent])] = [:]
        var order: [String] = []

        for event in remaining {
            let key = keyFormatter.string(from: event.startDate)
            if grouped[key] == nil {
                let label = monthFormatter.string(from: event.startDate)
                grouped[key] = (label: label, events: [])
                order.append(key)
            }
            grouped[key]!.events.append(event)
        }

        return order.compactMap { key in
            guard let group = grouped[key] else { return nil }
            return (key: key, label: group.label, events: group.events)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top: app branding + action buttons (event tabs only)
                if selectedTab != .settings {
                    topSection
                }

                // Tab content
                Group {
                    switch selectedTab {
                    case .pending:
                        pendingList
                    case .saved:
                        processedList
                    case .settings:
                        SettingsFormContent()
                    }
                }
                .id(selectedTab)
                .transition(.asymmetric(
                    insertion: .move(edge: slideDirection),
                    removal: .move(edge: slideDirection == .trailing ? .leading : .trailing)
                ))
                .frame(maxHeight: .infinity)
                .gesture(
                    selectedTab == .settings ? nil :
                    DragGesture(minimumDistance: 50, coordinateSpace: .local)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            if value.translation.width < -50 && selectedTab == .pending {
                                slideDirection = .trailing
                                withAnimation(.easeInOut(duration: 0.25)) { selectedTab = .saved }
                            } else if value.translation.width > 50 && selectedTab == .saved {
                                slideDirection = .leading
                                withAnimation(.easeInOut(duration: 0.25)) { selectedTab = .pending }
                            }
                        }
                )

                // Bottom: tab bar
                tabBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showCamera) {
                ZStack(alignment: .topLeading) {
                    ImagePicker(sourceType: .camera) { image in
                        processor.processImage(image, context: modelContext)
                    }
                    .ignoresSafeArea()

                    Button {
                        showCamera = false
                    } label: {
                        Label("Events", systemImage: "calendar")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                    .padding(.top, 16)
                    .padding(.leading, 16)
                }
            }
            .sheet(isPresented: $showLibrary) {
                ImagePicker(sourceType: .photoLibrary) { image in
                    processor.processImage(image, context: modelContext)
                }
                .ignoresSafeArea()
            }
            .sheet(item: $correctionEvent) { event in
                DateCorrectionSheet(event: event)
            }
            .navigationDestination(for: UUID.self) { eventID in
                EventDetailView(eventID: eventID, processor: processor)
            }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                showCamera = openCameraOnLaunch
            }
            processor.locationService.requestLocation()
            processor.recoverStuckEvents(context: modelContext)
            processor.autoRetryEligibleEvents(context: modelContext)
            DigestService.flushPendingEvents(context: modelContext)
            consumePendingShares()
            registerForShareNotifications()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                processor.recoverStuckEvents(context: modelContext)
                DigestService.flushPendingEvents(context: modelContext)
                consumePendingShares()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("com.eventsnap.pendingSharesAvailable"))) { _ in
            consumePendingShares()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            guard FeedbackService.isTestFlight else { return }
            screenshotData = FeedbackService.captureScreenshot()
            showFeedbackPrompt = true
        }
        .alert("Send Feedback?", isPresented: $showFeedbackPrompt) {
            Button("Send Feedback") {
                if MFMailComposeViewController.canSendMail() {
                    showFeedbackSheet = true
                }
            }
            Button("Not Now", role: .cancel) {
                screenshotData = nil
            }
        } message: {
            Text("Would you like to send feedback about what you see? Your screenshot will be attached.")
        }
        .sheet(isPresented: $showFeedbackSheet) {
            FeedbackMailView(screenshotData: screenshotData) { didSend, _ in
                if didSend {
                    FeedbackService.logFeedback(messagePreview: "(sent via screenshot)", hadScreenshot: screenshotData != nil)
                }
                screenshotData = nil
            }
        }
    }

    // MARK: - Top section

    private var topSection: some View {
        VStack(spacing: 10) {
            Button {
                showCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                showLibrary = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

}
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    guard tab != selectedTab else { return }
                    let tabIndex = Tab.allCases.firstIndex(of: tab)!
                    let currentIndex = Tab.allCases.firstIndex(of: selectedTab)!
                    slideDirection = tabIndex > currentIndex ? .trailing : .leading
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tabIcon(for: tab))
                            .font(.title3)
                            .scaleEffect(selectedTab == tab ? 1.0 : 0.9)
                            .animation(.easeInOut(duration: 0.2), value: selectedTab)
                        Text(tab.rawValue)
                            .font(.caption)
                    }
                    .foregroundStyle(selectedTab == tab ? .blue : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(.bottom, 4)
        .background(.bar)
    }

    private func tabIcon(for tab: Tab) -> String {
        switch tab {
        case .pending: "tray.full"
        case .saved: "checkmark.circle"
        case .settings: "gearshape"
        }
    }

    // MARK: - Pending list

    private var pendingList: some View {
        Group {
            if pendingEvents.isEmpty {
                ContentUnavailableView {
                    Label("No Pending Events", systemImage: "tray")
                } description: {
                    Text("Take a photo of an event poster or share from another app")
                }
            } else {
                List {
                    ForEach(pendingEvents) { event in
                        if event.status == .ready {
                            NavigationLink(value: event.id) {
                                EventRowView(event: event)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    let details = event.toEventDetails()
                                    CalendarService.openGoogleCalendar(event: details)
                                    let googleCalendarURL = CalendarService.googleCalendarURL(for: details)?.absoluteString
                                    event.status = .added
                                    event.updatedAt = Date()
                                    event.googleCalendarURL = googleCalendarURL
                                    DigestService.dequeueEvent(event, context: modelContext)
                                } label: {
                                    Label("Add", systemImage: "calendar.badge.plus")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    DigestService.dequeueEvent(event, context: modelContext)
                                    modelContext.delete(event)
                                } label: {
                                    Label("Dismiss", systemImage: "xmark")
                                }
                            }
                        } else if event.status == .failed && event.needsDateCorrection {
                            Button {
                                correctionEvent = event
                            } label: {
                                EventRowView(event: event)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    modelContext.delete(event)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        } else if event.status == .failed && event.isPastEvent {
                            NavigationLink(value: event.id) {
                                EventRowView(event: event)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    modelContext.delete(event)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        } else if event.status == .failed {
                            EventRowView(event: event)
                                .swipeActions(edge: .leading) {
                                    if event.canRetry {
                                        Button {
                                            processor.retryEvent(event, context: modelContext)
                                        } label: {
                                            Label("Retry", systemImage: "arrow.clockwise")
                                        }
                                        .tint(.blue)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        modelContext.delete(event)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        } else {
                            // Processing
                            EventRowView(event: event)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Processed list

    private var processedList: some View {
        Group {
            if processedEvents.isEmpty {
                ContentUnavailableView {
                    Label("No Processed Events", systemImage: "checkmark.circle")
                } description: {
                    Text("Events you add to your calendar will appear here")
                }
            } else {
                List {
                    if !upcomingProcessed.isEmpty {
                        Section("Coming Up") {
                            ForEach(upcomingProcessed) { event in
                                NavigationLink(value: event.id) {
                                    EventRowView(event: event)
                                }
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    modelContext.delete(upcomingProcessed[index])
                                }
                            }
                        }
                    }

                    ForEach(remainingByMonth, id: \.key) { group in
                        Section(isExpanded: Binding(
                            get: { expandedMonths.contains(group.key) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedMonths.insert(group.key)
                                } else {
                                    expandedMonths.remove(group.key)
                                }
                            }
                        )) {
                            ForEach(group.events) { event in
                                NavigationLink(value: event.id) {
                                    EventRowView(event: event)
                                }
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    modelContext.delete(group.events[index])
                                }
                            }
                        } header: {
                            Text("\(group.label) (\(group.events.count))")
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: - Share Extension consumption

    private func consumePendingShares() {
        let pendingShares = SharedContainerService.loadPendingShares()
        for (share, imageData) in pendingShares {
            processor.processSharedItem(share, imageData: imageData, context: modelContext)
            SharedContainerService.deletePendingShare(share)
        }
        if !pendingShares.isEmpty {
            showCamera = false
            selectedTab = .pending
        }
    }

    private func registerForShareNotifications() {
        let name = "com.eventsnap.newShareAvailable" as CFString
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("com.eventsnap.pendingSharesAvailable"),
                        object: nil
                    )
                }
            },
            name,
            nil,
            .deliverImmediately
        )
    }
}

// MARK: - Date/Time Correction Sheet

private struct DateCorrectionSheet: View {
    let event: PersistedEvent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var timingChoice: TimingChoice = .specificTime

    private enum TimingChoice: String, CaseIterable {
        case allDay = "All Day"
        case specificTime = "Specific Time"
    }

    private var needsDate: Bool { !event.hasExplicitDate }
    private var needsTime: Bool { !event.hasExplicitTime && !event.isAllDay }

    private var datePickerComponents: DatePickerComponents {
        if needsDate && needsTime && timingChoice == .specificTime {
            return [.date, .hourAndMinute]
        }
        if needsDate { return .date }
        return .hourAndMinute
    }

    private var headerText: String {
        if needsDate && needsTime {
            return "Set the date and timing"
        } else if needsDate {
            return "Enter the date"
        } else {
            return "Set the event timing"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(event.title)
                        .font(.headline)
                    if !event.venue.isEmpty {
                        Text(event.venue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if needsTime {
                    Section {
                        Picker("Timing", selection: $timingChoice) {
                            ForEach(TimingChoice.allCases, id: \.self) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                        if timingChoice == .allDay {
                            Text("If you don't know the timing, create an All-Day event.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if timingChoice == .allDay && !needsDate {
                    // All day chosen, date already known — no pickers needed
                } else if timingChoice == .allDay && needsDate {
                    Section("Enter the date") {
                        DatePicker("Date", selection: $startDate, displayedComponents: .date)
                    }
                } else {
                    Section(needsDate ? "Enter the date and time" : "Enter the time") {
                        DatePicker("Start", selection: $startDate, displayedComponents: datePickerComponents)
                        DatePicker("End", selection: $endDate, displayedComponents: datePickerComponents)
                    }
                }

                Section {
                    Button {
                        applyCorrection()
                        dismiss()
                    } label: {
                        Label("Confirm", systemImage: "checkmark.circle")
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
            .navigationTitle("Complete Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            startDate = event.startDate
            endDate = event.endDate
        }
        .onChange(of: startDate) { _, newStart in
            let offset = event.endDate.timeIntervalSince(event.startDate)
            endDate = newStart.addingTimeInterval(offset)
        }
    }

    private func applyCorrection() {
        let calendar = Calendar.current

        if timingChoice == .allDay {
            // All-day event: set start to beginning of day, end to end of day
            let day = needsDate ? startDate : event.startDate
            event.startDate = calendar.startOfDay(for: day)
            event.endDate = calendar.startOfDay(for: day).addingTimeInterval(86399)
            event.isAllDay = true
        } else if needsDate && !needsTime {
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: event.startDate)
            var merged = DateComponents()
            merged.year = dateComponents.year
            merged.month = dateComponents.month
            merged.day = dateComponents.day
            merged.hour = timeComponents.hour
            merged.minute = timeComponents.minute
            merged.second = timeComponents.second
            if let corrected = calendar.date(from: merged) {
                event.startDate = corrected
            } else {
                event.startDate = startDate
            }

            let endDateComps = calendar.dateComponents([.year, .month, .day], from: endDate)
            let endTimeComps = calendar.dateComponents([.hour, .minute, .second], from: event.endDate)
            var endMerged = DateComponents()
            endMerged.year = endDateComps.year
            endMerged.month = endDateComps.month
            endMerged.day = endDateComps.day
            endMerged.hour = endTimeComps.hour
            endMerged.minute = endTimeComps.minute
            endMerged.second = endTimeComps.second
            if let corrected = calendar.date(from: endMerged) {
                event.endDate = corrected
            } else {
                event.endDate = endDate
            }
        } else if needsTime && !needsDate {
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: event.startDate)
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: startDate)
            var merged = DateComponents()
            merged.year = dateComponents.year
            merged.month = dateComponents.month
            merged.day = dateComponents.day
            merged.hour = timeComponents.hour
            merged.minute = timeComponents.minute
            merged.second = timeComponents.second
            if let corrected = calendar.date(from: merged) {
                event.startDate = corrected
            } else {
                event.startDate = startDate
            }

            let endDateComps = calendar.dateComponents([.year, .month, .day], from: event.endDate)
            let endTimeComps = calendar.dateComponents([.hour, .minute, .second], from: endDate)
            var endMerged = DateComponents()
            endMerged.year = endDateComps.year
            endMerged.month = endDateComps.month
            endMerged.day = endDateComps.day
            endMerged.hour = endTimeComps.hour
            endMerged.minute = endTimeComps.minute
            endMerged.second = endTimeComps.second
            if let corrected = calendar.date(from: endMerged) {
                event.endDate = corrected
            } else {
                event.endDate = endDate
            }
        } else {
            event.startDate = startDate
            event.endDate = endDate
        }

        event.hasExplicitDate = true
        event.hasExplicitTime = true
        event.status = .ready
        event.errorMessage = nil
        event.updatedAt = Date()
        event.googleCalendarURL = CalendarService.googleCalendarURL(
            for: event.toEventDetails()
        )?.absoluteString

        DigestService.queueEvent(event, context: modelContext)
        DigestService.flushPendingEvents(context: modelContext)
    }
}
