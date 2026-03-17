import SwiftUI
import SwiftData

struct EventListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \PersistedEvent.createdAt, order: .reverse) private var events: [PersistedEvent]
    @State private var processor = BackgroundEventProcessor()
    @State private var showCamera = true
    @State private var showLibrary = false
    @State private var showDebugLog = false
    @State private var selectedTab: Tab = .pending

    enum Tab: String, CaseIterable {
        case pending = "Pending"
        case processed = "Processed"
    }

    private var pendingEvents: [PersistedEvent] {
        events.filter { $0.status == .processing || $0.status == .ready || $0.status == .failed }
    }

    private var processedEvents: [PersistedEvent] {
        events.filter { $0.status == .added }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top: app branding + action buttons
                topSection

                // Tab content
                Group {
                    switch selectedTab {
                    case .pending:
                        pendingList
                    case .processed:
                        processedList
                    }
                }
                .frame(maxHeight: .infinity)

                // Bottom: tab bar
                tabBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDebugLog = true
                    } label: {
                        Image(systemName: "ladybug")
                    }
                }
            }
            .sheet(isPresented: $showDebugLog) {
                NavigationStack {
                    ScrollView {
                        Text(SharedContainerService.readDebugLog() ?? "No debug log available")
                            .font(.caption.monospaced())
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .navigationTitle("Share Debug Log")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Clear") {
                                SharedContainerService.clearDebugLog()
                                showDebugLog = false
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showDebugLog = false }
                        }
                    }
                }
            }
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
            .navigationDestination(for: UUID.self) { eventID in
                EventDetailView(eventID: eventID, processor: processor)
            }
        }
        .onAppear {
            processor.locationService.requestLocation()
            processor.recoverStuckEvents(context: modelContext)
            processor.autoRetryEligibleEvents(context: modelContext)
            consumePendingShares()
            registerForShareNotifications()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                processor.recoverStuckEvents(context: modelContext)
                showCamera = true
                consumePendingShares()  // Overrides to false if shares arrived
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("com.eventsnap.pendingSharesAvailable"))) { _ in
            consumePendingShares()
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab == .pending ? "tray.full" : "checkmark.circle")
                            .font(.title3)
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
                                    CalendarService.openGoogleCalendar(event: event.toEventDetails())
                                    event.status = .added
                                    event.updatedAt = Date()
                                } label: {
                                    Label("Add", systemImage: "calendar.badge.plus")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    modelContext.delete(event)
                                } label: {
                                    Label("Dismiss", systemImage: "xmark")
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
                    ForEach(processedEvents) { event in
                        NavigationLink(value: event.id) {
                            EventRowView(event: event)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(processedEvents[index])
                        }
                    }
                }
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
