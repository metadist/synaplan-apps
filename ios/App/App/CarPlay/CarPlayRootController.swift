import CarPlay
import UIKit

/// Owns the CarPlay template hierarchy: one list (new conversation + recent
/// chats) and, while talking, the voice control template on top of it. No
/// chat content is ever shown as text — the car only gets titles and times.
@MainActor
final class CarPlayRootController {
    private let interfaceController: CPInterfaceController
    private let client: SynaplanCarClient
    private let store: CarSessionStore
    private let listTemplate: CPListTemplate
    private var voiceTemplate: CPVoiceControlTemplate?
    private var engine: VoiceConversationEngine?
    private var usesOverlay = false
    private var loadTask: Task<Void, Never>?
    private var sessionObserver: NSObjectProtocol?

    init(interfaceController: CPInterfaceController, client: SynaplanCarClient = .shared, store: CarSessionStore = .shared) {
        self.interfaceController = interfaceController
        self.client = client
        self.store = store
        listTemplate = CPListTemplate(title: CarPlayStrings.text("root.title"), sections: [])
    }

    func start() {
        interfaceController.setRootTemplate(listTemplate, animated: false, completion: nil)
        sessionObserver = NotificationCenter.default.addObserver(
            forName: CarSessionStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    func stop() {
        loadTask?.cancel()
        engine?.end()
        engine = nil
        if let sessionObserver {
            NotificationCenter.default.removeObserver(sessionObserver)
        }
        sessionObserver = nil
    }

    // MARK: - List

    private func reload() {
        loadTask?.cancel()
        guard client.isSignedIn else {
            showEmpty(title: "root.signedOutTitle", subtitle: "root.signedOutDetail")
            return
        }
        if listTemplate.sections.isEmpty {
            showEmpty(title: "root.loading", subtitle: nil)
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let chats = try await client.listChats()
                if Task.isCancelled { return }
                showChats(chats)
            } catch is CancellationError {
                return
            } catch CarClientError.signedOut {
                showEmpty(title: "root.signedOutTitle", subtitle: "root.signedOutDetail")
            } catch {
                showUnreachable()
            }
        }
    }

    private func showEmpty(title: String, subtitle: String?) {
        listTemplate.emptyViewTitleVariants = [CarPlayStrings.text(title)]
        listTemplate.emptyViewSubtitleVariants = subtitle.map { [CarPlayStrings.text($0)] } ?? []
        listTemplate.updateSections([])
    }

    private func showUnreachable() {
        let retry = CPListItem(
            text: CarPlayStrings.text("root.retry"),
            detailText: CarPlayStrings.text("root.unreachableDetail"),
            image: UIImage(systemName: "arrow.clockwise")
        )
        retry.handler = { [weak self] _, completion in
            Task { @MainActor in
                self?.reload()
                completion()
            }
        }
        listTemplate.updateSections([
            CPListSection(items: [retry], header: CarPlayStrings.text("root.unreachableTitle"), sectionIndexTitle: nil),
        ])
    }

    private func showChats(_ chats: [CarChatSummary]) {
        let newConversation = CPListItem(
            text: CarPlayStrings.text("root.newConversation"),
            detailText: chats.isEmpty ? CarPlayStrings.text("root.empty") : CarPlayStrings.text("root.newConversationDetail"),
            image: UIImage(systemName: "waveform")
        )
        newConversation.handler = { [weak self] _, completion in
            Task { @MainActor in
                self?.startConversation(chatId: nil)
                completion()
            }
        }
        var sections = [CPListSection(items: [newConversation])]

        let limit = max(0, min(SynaplanCarClient.chatListLimit, CPListTemplate.maximumItemCount - 1))
        let items: [CPListItem] = chats.prefix(limit).map { chat in
            let item = CPListItem(
                text: chat.title.isEmpty ? CarPlayStrings.text("root.untitledChat") : chat.title,
                detailText: chat.updatedAt.map { CarPlayStrings.relativeTime($0) },
                image: chat.pinned ? UIImage(systemName: "pin.fill") : nil
            )
            item.accessoryType = .none
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    self?.startConversation(chatId: chat.id)
                    completion()
                }
            }
            return item
        }
        if !items.isEmpty {
            sections.append(CPListSection(items: items, header: CarPlayStrings.text("root.recentChats"), sectionIndexTitle: nil))
        }
        listTemplate.updateSections(sections)
    }

    // MARK: - Conversation

    private func startConversation(chatId: Int?) {
        guard engine == nil else { return }
        guard #available(iOS 26.4, *) else {
            showAlert(messageKey: "root.requiresUpdate")
            return
        }
        let engine = VoiceConversationEngine(chatId: chatId, client: client, store: store)
        engine.delegate = self
        self.engine = engine

        let template = makeVoiceTemplate()
        voiceTemplate = template
        presentVoiceTemplate(template)
        engine.start()
    }

    @available(iOS 26.4, *)
    private func makeVoiceTemplate() -> CPVoiceControlTemplate {
        let states = VoiceState.allCases.map { state -> CPVoiceControlState in
            let control = CPVoiceControlState(
                identifier: state.rawValue,
                titleVariants: Self.titleVariants(for: state),
                image: Self.image(for: state),
                repeats: false
            )
            control.actionButtons = Array(actionButtons(for: state).prefix(CPVoiceControlState.maximumActionButtonCount))
            return control
        }
        return CPVoiceControlTemplate(voiceControlStates: states)
    }

    @available(iOS 26.4, *)
    private func actionButtons(for state: VoiceState) -> [CPButton] {
        let muteSymbol = state == .muted ? "mic.fill" : "mic.slash.fill"
        let mute = CPButton(image: Self.symbol(muteSymbol, size: 28)) { [weak self] _ in
            Task { @MainActor in self?.engine?.toggleMute() }
        }
        mute.title = CarPlayStrings.text(state == .muted ? "button.unmute" : "button.mute")
        let end = CPButton(image: Self.symbol("xmark", size: 28)) { [weak self] _ in
            Task { @MainActor in self?.engine?.end() }
        }
        end.title = CarPlayStrings.text("button.end")
        return [mute, end]
    }

    private func presentVoiceTemplate(_ template: CPVoiceControlTemplate) {
        if #available(iOS 27.0, *) {
            usesOverlay = true
            interfaceController.showOverlayTemplate(template, animated: true) { [weak self] success, _ in
                guard !success else { return }
                Task { @MainActor in
                    self?.usesOverlay = false
                    self?.interfaceController.presentTemplate(template, animated: true, completion: nil)
                }
            }
        } else {
            usesOverlay = false
            interfaceController.presentTemplate(template, animated: true, completion: nil)
        }
    }

    private func dismissVoiceTemplate(then next: @escaping () -> Void) {
        voiceTemplate = nil
        if usesOverlay, #available(iOS 27.0, *) {
            interfaceController.hideOverlayTemplate(animated: true) { _, _ in
                Task { @MainActor in next() }
            }
        } else {
            interfaceController.dismissTemplate(animated: true) { _, _ in
                Task { @MainActor in next() }
            }
        }
    }

    private func showAlert(messageKey: String) {
        let ok = CPAlertAction(title: CarPlayStrings.text("alert.ok"), style: .default) { [weak self] _ in
            self?.interfaceController.dismissTemplate(animated: true, completion: nil)
        }
        let alert = CPAlertTemplate(titleVariants: [CarPlayStrings.text(messageKey)], actions: [ok])
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
    }

    // MARK: - Appearance

    private static func titleVariants(for state: VoiceState) -> [String] {
        switch state {
        case .connecting: return [CarPlayStrings.text("voice.connecting")]
        case .listening: return [CarPlayStrings.text("voice.listening"), CarPlayStrings.text("voice.listeningShort")]
        case .thinking: return [CarPlayStrings.text("voice.thinking")]
        case .speaking: return [CarPlayStrings.text("voice.speaking")]
        case .muted: return [CarPlayStrings.text("voice.muted")]
        }
    }

    private static func image(for state: VoiceState) -> UIImage? {
        switch state {
        case .connecting: return symbol("antenna.radiowaves.left.and.right", size: 72)
        case .listening: return symbol("waveform", size: 72)
        case .thinking: return symbol("ellipsis", size: 72)
        case .speaking: return symbol("speaker.wave.2.fill", size: 72)
        case .muted: return symbol("mic.slash.fill", size: 72)
        }
    }

    private static func symbol(_ name: String, size: CGFloat) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
        return UIImage(systemName: name, withConfiguration: configuration) ?? UIImage()
    }
}

extension CarPlayRootController: VoiceConversationEngineDelegate {
    func voiceEngine(_ engine: VoiceConversationEngine, didChange state: VoiceState) {
        guard engine === self.engine else { return }
        voiceTemplate?.activateVoiceControlState(withIdentifier: state.rawValue)
    }

    func voiceEngine(_ engine: VoiceConversationEngine, didEndWith reason: VoiceEndReason, chatId: Int?) {
        guard engine === self.engine else { return }
        self.engine = nil
        dismissVoiceTemplate { [weak self] in
            guard let self else { return }
            if let key = reason.messageKey {
                showAlert(messageKey: key)
            }
            reload()
        }
    }
}
