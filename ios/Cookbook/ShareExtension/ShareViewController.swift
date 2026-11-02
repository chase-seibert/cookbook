import UIKit
import UniformTypeIdentifiers
import SafariServices

final class ShareViewController: UIViewController {
    private let successIcon = UIImageView()
    private let successTitleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var isQueued = false
    private var isWorking = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        successIcon.image = UIImage(systemName: "checkmark.circle.fill")
        successIcon.tintColor = .systemGreen
        successIcon.contentMode = .scaleAspectFit
        successIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        successIcon.isHidden = true

        successTitleLabel.text = "Sent to Cookbook"
        successTitleLabel.font = .boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .title2).pointSize)
        successTitleLabel.textAlignment = .center
        successTitleLabel.isHidden = true

        messageLabel.text = "Reading the shared page or recipe file…"
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        actionButton.setTitle("Send to Cookbook", for: .normal)
        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        actionButton.addTarget(self, action: #selector(handleAction), for: .touchUpInside)
        actionButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [successIcon, successTitleLabel, messageLabel, actionButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        DispatchQueue.main.async { [weak self] in self?.receiveFile() }
    }

    @objc private func handleAction() {
        if isQueued {
            extensionContext?.completeRequest(returningItems: nil)
        } else if !isWorking {
            receiveFile()
        }
    }

    private func receiveFile() {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        let sharedWebPage = providers.contains { provider in
            provider.registeredTypeIdentifiers.contains { identifier in
                let type = UTType(identifier)
                let normalized = identifier.lowercased()
                return type?.conforms(to: .url) == true
                    || type?.conforms(to: .text) == true
                    || type?.conforms(to: .propertyList) == true
                    || normalized.contains("html")
                    || normalized.contains("webarchive")
            }
        }

        isWorking = true
        actionButton.isEnabled = false
        messageLabel.text = "Reading the shared page or recipe file…"

        Task {
            if let capture = await safariCapture(in: items) {
                do {
                    _ = try PaprikaShareInbox.enqueueWebCapture(capture)
                    await MainActor.run {
                        showQueuedConfirmation(isWebCapture: true)
                    }
                    return
                } catch {
                    await MainActor.run { showError(error.localizedDescription) }
                    return
                }
            }

            guard !providers.isEmpty else {
                await MainActor.run {
                    showError("Safari did not provide page text. Allow Cookbook access to this webpage in Safari, then share it again.")
                }
                return
            }

            await MainActor.run {
                messageLabel.text = sharedWebPage ? "Reading the Safari page…" : "Preparing your Paprika file…"
            }
            var lastError: Error = PaprikaShareInbox.ShareInboxError.unsupportedFile
            for provider in providers {
                do {
                    let data = try await loadData(from: provider)
                    _ = try PaprikaShareInbox.enqueue(data)
                    await MainActor.run {
                        showQueuedConfirmation(isWebCapture: false)
                    }
                    return
                } catch {
                    lastError = error
                }
            }
            await MainActor.run {
                if sharedWebPage {
                    showError("Safari shared this page’s link but not its content. Allow Cookbook access to the webpage, then try again.")
                } else {
                    showError("This share did not contain a supported Paprika recipe archive. In Safari, choose Cookbook while sharing the recipe webpage.")
                }
            }
        }
    }

    private func safariCapture(in items: [NSExtensionItem]) async -> PaprikaShareInbox.WebCapture? {
        for item in items {
            if let values = item.userInfo?[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any],
               let capture = webCapture(from: values) {
                return capture
            }

            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                let item: NSSecureCoding? = try? await withCheckedThrowingContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { loadedItem, error in
                        if let loadedItem {
                            continuation.resume(returning: loadedItem)
                        } else {
                            continuation.resume(throwing: error ?? PaprikaShareInbox.ShareInboxError.unsupportedFile)
                        }
                    }
                }
                let dictionary = (item as? [String: Any]) ?? ((item as? NSDictionary) as? [String: Any])
                guard let dictionary else { continue }
                let values = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] ?? dictionary
                if let capture = webCapture(from: values) { return capture }
            }
        }
        return nil
    }

    private func webCapture(from values: [String: Any]) -> PaprikaShareInbox.WebCapture? {
        guard let url = values["url"] as? String, let text = values["text"] as? String else { return nil }
        return PaprikaShareInbox.WebCapture(url: url, title: values["title"] as? String ?? "", text: text, imageURL: values["imageURL"] as? String, capturedAt: .now)
    }

    private func loadData(from provider: NSItemProvider) async throws -> Data {
        var lastError: Error = PaprikaShareInbox.ShareInboxError.unsupportedFile
        for typeIdentifier in provider.registeredTypeIdentifiers {
            do {
                let data: Data = try await withCheckedThrowingContinuation { continuation in
                    provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, providerError in
                        if let url {
                            do { continuation.resume(returning: try Data(contentsOf: url)) }
                            catch { continuation.resume(throwing: error) }
                        } else {
                            continuation.resume(throwing: providerError ?? PaprikaShareInbox.ShareInboxError.unsupportedFile)
                        }
                    }
                }
                guard PaprikaShareInbox.isSupportedPayload(data) else {
                    lastError = PaprikaShareInbox.ShareInboxError.unsupportedFile
                    continue
                }
                return data
            } catch {
                lastError = error
            }
        }

        for typeIdentifier in provider.registeredTypeIdentifiers where UTType(typeIdentifier)?.conforms(to: .data) == true {
            do {
                let data: Data = try await withCheckedThrowingContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                        if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: error ?? PaprikaShareInbox.ShareInboxError.unsupportedFile) }
                    }
                }
                guard PaprikaShareInbox.isSupportedPayload(data) else {
                    lastError = PaprikaShareInbox.ShareInboxError.unsupportedFile
                    continue
                }
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func showError(_ message: String) {
        isWorking = false
        messageLabel.text = message
        actionButton.isEnabled = true
        actionButton.setTitle("Try Again", for: .normal)
        actionButton.isHidden = false
    }

    private func showQueuedConfirmation(isWebCapture: Bool) {
        isQueued = true
        isWorking = false
        successIcon.isHidden = false
        successTitleLabel.isHidden = false
        messageLabel.textColor = .label
        messageLabel.text = isWebCapture
            ? "Page captured. Open Cookbook to review the recipe and save it to your library."
            : "Paprika file sent to Cookbook. Open Cookbook to review the import."
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Done"
        configuration.baseBackgroundColor = .systemGreen
        actionButton.configuration = configuration
        actionButton.isEnabled = true
        actionButton.isHidden = false
    }
}
