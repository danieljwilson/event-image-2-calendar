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

            SharedContainerService.writeDebugLog("--- New share session ---")
            SharedContainerService.writeDebugLog("Extension items: \(extensionItems.count)")

            for item in extensionItems {
                guard let attachments = item.attachments else { continue }
                SharedContainerService.writeDebugLog("Attachments: \(attachments.count)")

                for (index, provider) in attachments.enumerated() {
                    SharedContainerService.writeDebugLog("Provider[\(index)] types: \(provider.registeredTypeIdentifiers)")

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

            // Extract URL from text if no URL attachment found (Instagram embeds URLs in text)
            if savedURL == nil, let text = savedText {
                if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
                    let range = NSRange(text.startIndex..., in: text)
                    if let match = detector.firstMatch(in: text, range: range),
                       let urlRange = Range(match.range, in: text) {
                        savedURL = String(text[urlRange])
                        SharedContainerService.writeDebugLog("Extracted URL from text: \(savedURL!)")
                    }
                }
            }

            // Single save: pass both image and URL when both are available
            SharedContainerService.writeDebugLog(
                "Saving: image=\(collectedImageData?.count ?? 0) bytes, " +
                "url=\(savedURL?.prefix(100) ?? "nil"), " +
                "text=\(savedText.map { "\($0.count) chars: \(String($0.prefix(200)))" } ?? "nil")"
            )
            var didSave = false
            if let imageData = collectedImageData {
                do {
                    _ = try SharedContainerService.savePendingShare(
                        imageData: imageData, sourceURL: savedURL, sourceText: savedText
                    )
                    didSave = true
                } catch {
                    SharedContainerService.writeDebugLog("savePendingShare failed (image): \(error.localizedDescription)")
                }
            } else if let url = savedURL {
                do {
                    _ = try SharedContainerService.savePendingShare(
                        imageData: nil, sourceURL: url, sourceText: savedText
                    )
                    didSave = true
                } catch {
                    SharedContainerService.writeDebugLog("savePendingShare failed (url): \(error.localizedDescription)")
                }
            } else if let text = savedText {
                do {
                    _ = try SharedContainerService.savePendingShare(
                        imageData: nil, sourceURL: nil, sourceText: text
                    )
                    didSave = true
                } catch {
                    SharedContainerService.writeDebugLog("savePendingShare failed (text): \(error.localizedDescription)")
                }
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
        // Use loadDataRepresentation + ImageIO downsampling to avoid
        // decompressing full-resolution images (which crashes share extensions)
        for typeId in provider.registeredTypeIdentifiers {
            guard UTType(typeId)?.conforms(to: .image) == true else { continue }
            SharedContainerService.writeDebugLog("  Trying loadDataRepresentation for \(typeId)")
            let rawData: Data? = await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: typeId) { data, error in
                    if let error {
                        SharedContainerService.writeDebugLog("  loadDataRepresentation error: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: data)
                }
            }
            if let rawData {
                SharedContainerService.writeDebugLog("  Got \(rawData.count) bytes, downsampling...")
                if let resized = ImageResizer.downsample(data: rawData) {
                    SharedContainerService.writeDebugLog("  Downsample success: \(resized.count) bytes")
                    return resized
                }
                SharedContainerService.writeDebugLog("  Downsample failed")
            }
        }
        SharedContainerService.writeDebugLog("  All image loading strategies failed")
        return nil
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    SharedContainerService.writeDebugLog("  loadURL error: \(error.localizedDescription)")
                }
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error {
                    SharedContainerService.writeDebugLog("  loadText error: \(error.localizedDescription)")
                }
                continuation.resume(returning: item as? String)
            }
        }
    }

    private func done() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
