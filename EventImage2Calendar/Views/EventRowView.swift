import SwiftUI

struct EventRowView: View {
    let event: PersistedEvent

    var body: some View {
        HStack(spacing: 12) {
            if let imageData = event.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: statusIcon)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title.isEmpty ? "Processing..." : event.title)
                    .font(.headline)
                    .lineLimit(1)

                if event.status == .processing {
                    ProgressView()
                        .controlSize(.small)
                } else if event.status == .failed {
                    Text(event.errorMessage ?? "Extraction failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else {
                    Text(event.startDate, style: .date)
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

            statusBadge
        }
    }

    private var statusIcon: String {
        switch event.status {
        case .processing: return "hourglass"
        case .failed: return "exclamationmark.triangle"
        case .ready: return "checkmark.circle"
        case .added: return "calendar.badge.checkmark"
        case .dismissed: return "xmark.circle"
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch event.status {
        case .added:
            Image(systemName: "calendar.badge.checkmark")
                .foregroundStyle(.green)
        case .dismissed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        case .ready:
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
        default:
            EmptyView()
        }
    }
}
