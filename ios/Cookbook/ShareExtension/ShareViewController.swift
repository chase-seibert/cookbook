import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var isQueued = false
    private var isWorking = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        messageLabel.text = "Send this Paprika file to Cookbook for review before importing."
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        actionButton.setTitle("Send to Cookbook", for: .normal)
        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        actionButton.addTarget(self, action: #selector(handleAction), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [messageLabel, actionButton])
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
    }

    @objc private func handleAction() {
        if isQueued {
            extensionContext?.completeRequest(returningItems: nil)
        } else if !isWorking {
            receiveFile()
        }
    }

    private func receiveFile() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap({ $0.attachments ?? [] }) ?? []
        guard !providers.isEmpty else {
            showError("Paprika did not provide a recipe file to share.")
            return
        }

        isWorking = true
        actionButton.isEnabled = false
        messageLabel.text = "Preparing your Paprika file…"

        Task {
            var lastError: Error = PaprikaShareInbox.ShareInboxError.unsupportedFile
            for provider in providers {
                do {
                    let data = try await loadData(from: provider)
                    _ = try PaprikaShareInbox.enqueue(data)
                    await MainActor.run {
                        isQueued = true
                        isWorking = false
                        messageLabel.text = "Ready in Cookbook. Open Cookbook to preview the recipe and choose what to import."
                        actionButton.isEnabled = true
                        actionButton.setTitle("Done", for: .normal)
                    }
                    return
                } catch {
                    lastError = error
                }
            }
            await MainActor.run { showError(lastError.localizedDescription) }
        }
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
    }
}
