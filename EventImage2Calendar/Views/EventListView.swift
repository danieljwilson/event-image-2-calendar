import SwiftUI
import SwiftData

struct EventListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \PersistedEvent.createdAt, order: .reverse) private var events: [PersistedEvent]
    @State private var processor = BackgroundEventProcessor()
    @State private var showCamera = true
    @State private var showLibrary = false

    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty {
                    emptyState
                } else {
                    eventList
                }
            }
            .navigationTitle("Events")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
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
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .background(.bar)
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
                consumePendingShares()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("com.eventsnap.pendingSharesAvailable"))) { _ in
            consumePendingShares()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Events", systemImage: "calendar.badge.plus")
        } description: {
            Text("Take a photo of an event poster to get started")
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

    private var eventList: some View {
        List {
            let readyEvents = events.filter { $0.status == .ready }
            if !readyEvents.isEmpty {
                Section("Ready") {
                    ForEach(readyEvents) { event in
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
                            Button {
                                event.status = .dismissed
                                event.updatedAt = Date()
                            } label: {
                                Label("Dismiss", systemImage: "xmark")
                            }
                            .tint(.red)
                        }
                    }
                }
            }

            let processingEvents = events.filter { $0.status == .processing }
            if !processingEvents.isEmpty {
                Section {
                    ForEach(processingEvents) { event in
                        EventRowView(event: event)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("Processing")
                        ProgressView()
                            .controlSize(.mini)
                        Text("(\(processingEvents.count))")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            let failedEvents = events.filter { $0.status == .failed }
            if !failedEvents.isEmpty {
                Section("Failed") {
                    ForEach(failedEvents) { event in
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
                    }
                }
            }

            let historyEvents = events.filter { $0.status == .added || $0.status == .dismissed }
            if !historyEvents.isEmpty {
                Section("History") {
                    ForEach(historyEvents) { event in
                        NavigationLink(value: event.id) {
                            EventRowView(event: event)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(historyEvents[index])
                        }
                    }
                }
            }
        }
        .navigationDestination(for: UUID.self) { eventID in
            EventDetailView(eventID: eventID, processor: processor)
        }
    }
}
