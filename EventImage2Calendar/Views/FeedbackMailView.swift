import SwiftUI
import MessageUI

struct FeedbackMailView: UIViewControllerRepresentable {
    let screenshotData: Data?
    let onDismiss: (_ didSend: Bool, _ messageBody: String?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients([FeedbackService.feedbackEmail])
        mail.setSubject("[Event Snap Feedback] v\(version) (\(build))")
        mail.setMessageBody("\n\n\(FeedbackService.deviceMetadata())", isHTML: false)

        if let screenshot = screenshotData {
            mail.addAttachmentData(screenshot, mimeType: "image/jpeg", fileName: "screenshot.jpg")
        }

        if let debugLog = SharedContainerService.readDebugLog(),
           let logData = debugLog.data(using: .utf8), !debugLog.isEmpty {
            mail.addAttachmentData(logData, mimeType: "text/plain", fileName: "debug_log.txt")
        }

        return mail
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: FeedbackMailView

        init(_ parent: FeedbackMailView) {
            self.parent = parent
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            let didSend = result == .sent

            // Extract the user-typed portion of the message body
            var messageBody: String?
            if didSend {
                // The body isn't directly accessible after send, so we pass nil
                // The caller can use whatever context it has
                messageBody = nil
            }

            parent.onDismiss(didSend, messageBody)
            parent.dismiss()
        }
    }
}
