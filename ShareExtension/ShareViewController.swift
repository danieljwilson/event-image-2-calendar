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
            var savedImage = false
            var savedURL: String?
            var savedText: String?

            for item in extensionItems {
                guard let attachments = item.attachments else { continue }

                for provider in attachments {
                    // Priority 1: Images (screenshots, photos, etc.)
                    if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        if let imageData = await loadImage(from: provider) {
                            let _ = try? SharedContainerService.savePendingShare(
                                imageData: imageData, sourceURL: nil, sourceText: nil
                            )
                            savedImage = true
                        }
                    }
                    // Priority 2: URLs (web pages, Instagram links, etc.)
                    else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        if let url = await loadURL(from: provider) {
                            savedURL = url.absoluteString
                        }
                    }
                    // Priority 3: Plain text
                    else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        if let text = await loadText(from: provider) {
                            savedText = text
                        }
                    }
                }
            }

            // Save URL-only or text-only shares if no image was saved
            if !savedImage {
                if let url = savedURL {
                    let _ = try? SharedContainerService.savePendingShare(
                        imageData: nil, sourceURL: url, sourceText: savedText
                    )
                } else if let text = savedText {
                    let _ = try? SharedContainerService.savePendingShare(
                        imageData: nil, sourceURL: nil, sourceText: text
                    )
                }
            }

            // Notify main app via Darwin notification
            let name = "com.eventsnap.newShareAvailable" as CFString
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(name),
                nil, nil, true
            )

            await MainActor.run {
                statusLabel.text = "Saved!"
                spinner.stopAnimating()
            }

            try? await Task.sleep(for: .milliseconds(600))
            done()
        }
    }

    // MARK: - Item loading helpers

    private func loadImage(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
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
