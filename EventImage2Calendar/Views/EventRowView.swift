import SwiftUI

struct EventRowView: View {
    let event: PersistedEvent

    var body: some View {
        HStack(spacing: 12) {
            // Left: status indicator
            leftIndicator

            // Center: event details
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title.isEmpty ? "Processing..." : event.title)
                    .font(.headline)
                    .lineLimit(1)

                if event.status == .processing {
                    Text("Extracting event details...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if event.status == .failed && event.needsDateCorrection {
                    Text(event.missingFieldDescription)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                    if !event.venue.isEmpty {
                        Text(event.venue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else if event.status == .failed {
                    Text(event.errorMessage ?? "Extraction failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    if event.retryCount > 0 {
                        Text(event.canRetry
                            ? "Retried \(event.retryCount)x — swipe to retry"
                            : "Max retries reached")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(event.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !event.venue.isEmpty {
                        Text(event.venue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Right: action indicator
            rightIndicator
        }
    }

    @ViewBuilder
    private var leftIndicator: some View {
        switch event.status {
        case .added:
            Image(systemName: "calendar.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 28)
        case .processing:
            RoundedRectangle(cornerRadius: 2)
                .fill(.yellow)
                .frame(width: 4, height: 44)
        case .ready:
            RoundedRectangle(cornerRadius: 2)
                .fill(.green)
                .frame(width: 4, height: 44)
        case .failed:
            RoundedRectangle(cornerRadius: 2)
                .fill(event.needsDateCorrection ? .orange : .red)
                .frame(width: 4, height: 44)
        case .dismissed:
            RoundedRectangle(cornerRadius: 2)
                .fill(.secondary)
                .frame(width: 4, height: 44)
        }
    }

    @ViewBuilder
    private var rightIndicator: some View {
        switch event.status {
        case .processing:
            ProgressView()
                .controlSize(.small)
        case .ready:
            EmptyView()  // NavigationLink provides the chevron
        case .failed:
            if event.needsDateCorrection {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        case .added, .dismissed:
            EmptyView()
        }
    }
}
