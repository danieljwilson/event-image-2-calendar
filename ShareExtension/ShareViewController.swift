import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processSharedItems()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Saving to Event Snap..."
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - Process shared content

    private func processSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            done()
            return
        }

        Task {
            var collectedImageData: Data?
            var savedURL: String?
            var savedText: String?

            for item in extensionItems {
                guard let attachments = item.attachments else { continue }

                for provider in attachments {
                    // Collect image (a provider can conform to multiple types)
                    if collectedImageData == nil &&
                       provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        if let data = await loadImage(from: provider) {
                            collectedImageData = data
                        }
                    }
                    // Also collect URL (not else-if — same provider may have both)
                    if savedURL == nil &&
                       provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        if let url = await loadURL(from: provider) {
                            savedURL = url.absoluteString
                        }
                    }
                    // Also collect text
                    if savedText == nil &&
                       provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        if let text = await loadText(from: provider) {
                            savedText = text
                        }
                    }
                }
            }

            // Single save: pass both image and URL when both are available
            var didSave = false
            if let imageData = collectedImageData {
                let _ = try? SharedContainerService.savePendingShare(
                    imageData: imageData, sourceURL: savedURL, sourceText: savedText
                )
                didSave = true
            } else if let url = savedURL {
                let _ = try? SharedContainerService.savePendingShare(
                    imageData: nil, sourceURL: url, sourceText: savedText
                )
                didSave = true
            } else if let text = savedText {
                let _ = try? SharedContainerService.savePendingShare(
                    imageData: nil, sourceURL: nil, sourceText: text
                )
                didSave = true
            }

            // Notify main app via Darwin notification
            if didSave {
                let name = "com.eventsnap.newShareAvailable" as CFString
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    CFNotificationName(name),
                    nil, nil, true
                )
            }

            await MainActor.run {
                statusLabel.text = didSave ? "Saved!" : "Could not process this content."
                spinner.stopAnimating()
            }

            try? await Task.sleep(for: .milliseconds(600))
            done()
        }
    }

    // MARK: - Item loading helpers

    private func loadImage(from provider: NSItemProvider) async -> Data? {
        // Modern API — handles Photos library, PHAsset-backed items, etc.
        if provider.canLoadObject(ofClass: UIImage.self) {
            let image: UIImage? = await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
            if let image, let data = image.resizedForAPI() {
                return data
            }
        }

        // Legacy fallback for providers that don't support loadObject
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                var imageData: Data?
                if let url = item as? URL,
                   let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    imageData = image.resizedForAPI()
                } else if let image = item as? UIImage {
                    imageData = image.resizedForAPI()
                } else if let data = item as? Data,
                          let image = UIImage(data: data) {
                    imageData = image.resizedForAPI()
                }
                continuation.resume(returning: imageData)
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    private func done() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
