import AVFoundation
import Foundation

/// Owns the `AVAudioSession`: category, activation, and the system-level
/// interruption / route-change notifications that every music app must handle.
final class AudioSessionManager {

    static let shared = AudioSessionManager()

    /// Fired when a phone call / Siri / alarm steals the audio session.
    var onInterruptionBegan: (() -> Void)?
    /// Fired when the interruption ends and playback may resume.
    var onInterruptionEnded: (() -> Void)?
    /// Fired when the output device disappears (headphones unplugged, AirPods removed).
    var onRouteLost: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    /// Must be called before playback starts. `.playback` is the category that
    /// enables background audio and lock-screen controls.
    func configure() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }

    func startObserving() {
        guard observers.isEmpty else { return }

        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        })
    }

    // MARK: - Handlers

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            onInterruptionBegan?()
        case .ended:
            if let rawOption = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: rawOption).contains(.shouldResume) {
                onInterruptionEnded?()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rawReason = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
              reason == .oldDeviceUnavailable else {
            return
        }
        // `.oldDeviceUnavailable` = the previously active output (e.g. headphones)
        // is gone. Pause so the user doesn't miss playback.
        onRouteLost?()
    }
}
