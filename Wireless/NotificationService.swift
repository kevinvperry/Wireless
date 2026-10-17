import Foundation
import UserNotifications

// Adapted from Autohop's NotificationService (MIT — original Autohop code),
// trimmed to the Sleep Schedule "still listening?" prompt.
// postSleepSchedulePrompt() fires a .timeSensitive notification (breaks
// through Sleep Focus/Do Not Disturb — requires the Time Sensitive
// Notifications entitlement) carrying a "Still Listening" action button. The
// action is a BACKGROUND action (empty options): tapping it on the lock screen
// confirms WITHOUT unlocking or opening the app. The delegate routes that tap
// to onStillListening (wired by MobilePlayer to
// SleepScheduleService.userResponded()). MobilePlayer clears the notification
// via clearSleepSchedulePrompt() whenever the prompt ends.
//
// PERMISSION TIMING: configure() (delegate + categories) runs at launch but
// does NOT prompt. Authorisation is requested only when the user turns on
// Sleep Schedule (SleepScheduleView).
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    static let shared = NotificationService()

    private override init() { super.init() }

    // MARK: - Sleep Schedule prompt identifiers

    private static let sleepPromptCategoryID = "sleepSchedulePrompt"
    private static let stillListeningActionID = "stillListening"
    private static let sleepPromptNotificationID = "sleep-schedule-prompt"

    /// Invoked (on the main actor) when the user taps "Still Listening" on the
    /// prompt notification — from the lock screen, banner or notification list.
    private var onStillListening: (@MainActor @Sendable () -> Void)?

    /// Set true if a "Still Listening" tap arrives before `onStillListening` is
    /// wired (e.g. a cold launch via the action). Flushed when the handler lands.
    private var pendingStillListening = false

    // MARK: - Permission & setup

    /// Installs this object as the notification-centre delegate and registers
    /// the Sleep Schedule action category. Called once at launch. Does NOT
    /// prompt for permission.
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let stillListening = UNNotificationAction(
            identifier: Self.stillListeningActionID,
            title: "Still Listening",
            // Empty options: runs in the background, no unlock, no app launch —
            // so a half-asleep listener can confirm straight from the lock screen.
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.sleepPromptCategoryID,
            actions: [stillListening],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// Requests notification authorisation. Call only in response to the user
    /// enabling Sleep Schedule. iOS shows the system prompt only the first
    /// time; later calls are no-ops.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    /// Allows MobilePlayer to flush a tap that arrived before its handler was wired.
    @MainActor
    func setStillListeningHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {
        onStillListening = handler
        if pendingStillListening {
            pendingStillListening = false
            Task { @MainActor in handler() }
        }
    }

    // MARK: - Sleep Schedule prompt

    /// Posts the lock-screen "Are you still listening?" prompt with a "Still
    /// Listening" action button. Time-sensitive so it breaks through Sleep Focus.
    func postSleepSchedulePrompt() {
        let content = UNMutableNotificationContent()
        content.title = "Are you still listening?"
        content.body = "Tap \u{201C}Still Listening\u{201D} to keep playing — otherwise Wireless fades out and pauses the station."
        content.sound = .default
        content.categoryIdentifier = Self.sleepPromptCategoryID
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: Self.sleepPromptNotificationID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Removes the prompt notification (delivered or pending). Called whenever
    /// the prompt ends — confirmed, timed out, or torn down.
    func clearSleepSchedulePrompt() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.sleepPromptNotificationID])
        center.removePendingNotificationRequests(withIdentifiers: [Self.sleepPromptNotificationID])
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == Self.stillListeningActionID {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let handler = self.onStillListening {
                    handler()
                } else {
                    self.pendingStillListening = true
                }
                self.clearSleepSchedulePrompt()
            }
        }
        completionHandler()
    }

    /// Show the prompt as a banner even when the app is foregrounded,
    /// alongside the in-app overlay.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
