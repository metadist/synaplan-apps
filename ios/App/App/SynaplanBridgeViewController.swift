import Capacitor
import UIKit

/// Capacitor 8 only auto-registers plugins from `packageClassList`. The
/// Shortcuts, CarPlay session, and live-voice bridges are app-owned, so they
/// are registered here after the bridge loads — the documented hook for local
/// native code. This runs before the WebView loads its first page.
class SynaplanBridgeViewController: CAPBridgeViewController {
    /// Chat composer is focused. The WebView stays full screen either way.
    private var wantsChatKeyboardDock = false
    /// True from the keyboard frame change that opened the chat dock until the
    /// keyboard has finished hiding, including a hide that starts after blur.
    private var trackingKeyboard = false
    private var bottomToHost: NSLayoutConstraint?
    private var bottomToKeyboard: NSLayoutConstraint?
    /// Offscreen view animated with the keyboard's duration and curve. Its
    /// presentation position is the keyboard overlap. A CSS transition cannot
    /// match that curve, so the page reads this instead of easing on its own.
    private let keyboardProbe = UIView()
    private var keyboardDisplayLink: CADisplayLink?
    private var animationStart: CGFloat = 0
    private var animationEnd: CGFloat = 0
    private var lastSample: CGFloat?
    private var lastPushedPx = -1
    private var framePushInFlight = false
    private var framePushPending: Int?

    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(SynaplanShortcutsPlugin())
        bridge?.registerPluginInstance(SynaplanCarSessionPlugin())
        bridge?.registerPluginInstance(SynaplanLiveVoicePlugin())
        bridge?.registerPluginInstance(SynaplanKeyboardDockPlugin())
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        installChatKeyboardHost()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardDidHide),
            name: UIResponder.keyboardDidHideNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardDidShow),
            name: UIResponder.keyboardDidShowNotification,
            object: nil
        )
    }

    deinit {
        keyboardDisplayLink?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    func setChatKeyboardDocked(_ enabled: Bool) {
        wantsChatKeyboardDock = enabled
        if enabled {
            trackingKeyboard = true
        }
        // Keep the WebView full screen. Animating its height makes WebKit
        // relayout the chat only when the keyboard animation ends, so the
        // messages jump. The page follows the keyboard frame instead.
        if isFollowingKeyboard {
            setFollowingKeyboard(false)
        }
    }

    /// The Capacitor root view is the WebView. The keyboard layout guide has to
    /// live on a view that stays full screen, otherwise shrinking the WebView
    /// makes the guide collapse and the height oscillates.
    private func installChatKeyboardHost() {
        guard let webView, bottomToHost == nil else { return }
        let host = UIView(frame: webView.bounds)
        host.backgroundColor = webView.backgroundColor
        // A floating iPad keyboard stays put. A docked iPhone keyboard is followed.
        host.keyboardLayoutGuide.followsUndockedKeyboard = false
        if #available(iOS 17.0, *) {
            // Hidden keyboard: the guide sits on the view bottom, not the home
            // indicator. The page's own safe-area padding covers that inset.
            host.keyboardLayoutGuide.usesBottomSafeArea = false
        }
        webView.translatesAutoresizingMaskIntoConstraints = false
        view = host
        host.addSubview(webView)
        let pinToHost = webView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        let pinToKeyboard = webView.bottomAnchor.constraint(equalTo: host.keyboardLayoutGuide.topAnchor)
        pinToKeyboard.isActive = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: host.topAnchor),
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            pinToHost,
        ])
        bottomToHost = pinToHost
        bottomToKeyboard = pinToKeyboard
        keyboardProbe.isUserInteractionEnabled = false
        keyboardProbe.backgroundColor = .clear
        keyboardProbe.autoresizingMask = []
        keyboardProbe.frame = CGRect(x: -30, y: 0, width: 1, height: 1)
        host.addSubview(keyboardProbe)
    }

    /// Pin the WebView to the keyboard layout guide for the whole dock session.
    /// The guide's top is the view bottom while the keyboard is hidden and the
    /// keyboard's top while it is docked, and UIKit animates that change.
    /// Waiting until the guide already overlapped left the constraint inactive,
    /// so the composer stayed under the keyboard.
    private func setFollowingKeyboard(_ follow: Bool) {
        guard let bottomToHost, let bottomToKeyboard else { return }
        guard bottomToKeyboard.isActive != follow else { return }
        if follow {
            bottomToHost.isActive = false
            bottomToKeyboard.isActive = true
        } else {
            bottomToKeyboard.isActive = false
            bottomToHost.isActive = true
        }
    }

    private var isFollowingKeyboard: Bool {
        bottomToKeyboard?.isActive == true
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        if wantsChatKeyboardDock {
            trackingKeyboard = true
        }
        guard trackingKeyboard else { return }
        let userInfo = notification.userInfo
        let duration = (userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curve = (userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7
        let endFrame = (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        let options = UIView.AnimationOptions(rawValue: curve << 16)
            .union([.beginFromCurrentState, .allowUserInteraction])
        animateProbe(to: keyboardOverlap(endFrame), duration: duration, options: options)
        startKeyboardTracking()
    }

    @objc private func keyboardDidShow() {
        guard trackingKeyboard else { return }
        pushKeyboardOverlap(keyboardProbe.center.y)
    }

    @objc private func keyboardDidHide() {
        if trackingKeyboard {
            trackingKeyboard = false
            stopKeyboardTracking()
            keyboardProbe.center.y = 0
            pushKeyboardOverlap(0)
        }
        guard !wantsChatKeyboardDock else { return }
        setFollowingKeyboard(false)
    }

    /// Keyboard frames are in screen coordinates. The overlap is how far the
    /// keyboard covers this view from the bottom, which is the distance the
    /// chat has to travel to sit on it.
    private func keyboardOverlap(_ screenFrame: CGRect) -> CGFloat {
        guard let window = view.window else {
            return max(0, UIScreen.main.bounds.maxY - screenFrame.minY)
        }
        let inWindow = window.convert(screenFrame, from: window.screen.coordinateSpace)
        let local = view.convert(inWindow, from: window)
        return max(0, view.bounds.maxY - local.minY)
    }

    /// Runs the probe on the keyboard's own duration and curve. UIKit does not
    /// give WebKit that animation, so a matching CSS ease always drifts.
    private func animateProbe(to end: CGFloat, duration: Double, options: UIView.AnimationOptions) {
        let start = keyboardProbe.layer.presentation()?.position.y ?? keyboardProbe.center.y
        animationStart = start
        animationEnd = end
        lastSample = nil
        UIView.performWithoutAnimation {
            self.keyboardProbe.center.y = start
        }
        guard duration > 0 else {
            keyboardProbe.center.y = end
            pushKeyboardOverlap(end)
            return
        }
        UIView.animate(withDuration: duration, delay: 0, options: options, animations: {
            self.keyboardProbe.center.y = end
        })
    }

    private func startKeyboardTracking() {
        guard keyboardDisplayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(trackKeyboardFrame))
        link.add(to: .main, forMode: .common)
        keyboardDisplayLink = link
    }

    private func stopKeyboardTracking() {
        keyboardDisplayLink?.invalidate()
        keyboardDisplayLink = nil
        lastSample = nil
        framePushPending = nil
    }

    @objc private func trackKeyboardFrame() {
        guard trackingKeyboard else { return }
        let presented = keyboardProbe.layer.presentation()?.position.y ?? keyboardProbe.center.y
        let current = max(0, presented)
        // The web process applies the value a frame later. One sample ahead
        // lands the chat on the keyboard instead of under it. Clamped to the
        // animation target so the page never travels past the keyboard.
        var sample = current
        if let lastSample {
            let predicted = current + (current - lastSample)
            if animationEnd >= animationStart {
                sample = min(animationEnd, max(current, predicted))
            } else {
                sample = max(animationEnd, min(current, predicted))
            }
        }
        lastSample = current
        pushKeyboardOverlap(sample)
    }

    private func pushKeyboardOverlap(_ overlap: CGFloat) {
        let px = max(0, Int(overlap.rounded()))
        if framePushInFlight {
            framePushPending = px
            return
        }
        guard px != lastPushedPx else { return }
        sendKeyboardFrame(px)
    }

    private func sendKeyboardFrame(_ px: Int) {
        guard let webView else { return }
        lastPushedPx = px
        framePushInFlight = true
        webView.evaluateJavaScript(
            "window.__synaplanKeyboardFrame&&window.__synaplanKeyboardFrame(\(px))"
        ) { [weak self] _, _ in
            guard let self else { return }
            self.framePushInFlight = false
            guard let pending = self.framePushPending else { return }
            self.framePushPending = nil
            guard pending != self.lastPushedPx else { return }
            self.sendKeyboardFrame(pending)
        }
    }
}
