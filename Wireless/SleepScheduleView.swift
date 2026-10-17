import SwiftUI

// Copied from Autohop's SleepScheduleView (MIT — original Autohop code) and
// adapted for live radio. Opened from the Sleep Timer sheet on the player.
// All controls write through SleepScheduleSettings immediately; disabling
// preserves hours/duration, enabling requests notification permission. Keep
// all five intervals. Autohop's End of Episode interval is omitted because a
// live stream has no episode boundary. Equal start/end means all day, not off.
// This view describes configuration, not live playback phase. The service owns
// countdowns, chimes, response handling, fade-out and manual-timer suspension.
struct SleepScheduleView: View {
    @ObservedObject var settings: SleepScheduleSettings
    @State private var showHowItWorks = false

    private static let durationPresets = SleepScheduleSettings.durationPresets

    var body: some View {
        Form {
            introduction
            if settings.enabled {
                activeHours
                checkInFrequency
                scheduleSummary
            }
            howItWorks
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .listSectionSpacing(WirelessLayoutMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .tint(.purple)
        .preferredColorScheme(.dark)
        .navigationTitle("Sleep Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var introduction: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.purple)
                        .accessibilityHidden(true)
                    Spacer()
                    Text(settings.enabled ? "On" : "Off")
                        .font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.purple.opacity(0.16), in: Capsule())
                        .accessibilityLabel(settings.enabled ? "Schedule on" : "Schedule off")
                }
                Text("Drift off.\nWe’ll fade out for you.")
                    .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose your listening hours and how often Wireless checks if you’re still awake. If you fall asleep, it fades out and pauses the station.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: enabledBinding) {
                    Label {
                        Text("Sleep Schedule").fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "bed.double.fill").foregroundStyle(.purple)
                    }
                    .font(.body)
                }
                .accessibilityIdentifier("sleepSchedule.enabled")
                Text(settings.enabled
                     ? "Changes save automatically. Your schedule repeats every day."
                     : "Off — your saved hours and check-in interval are kept for next time.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.35), lineWidth: 1))
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }

    private var activeHours: some View {
        card("Active Hours", icon: "moon.stars", explanation: "Choose when Sleep Schedule can check in. It only counts time while you’re playing a station.") {
            timePicker("Start", selection: startTimeBinding, identifier: "sleepSchedule.start")
            Divider()
            timePicker("End", selection: endTimeBinding, identifier: "sleepSchedule.end")
            Text(windowDescription)
                .font(.subheadline).foregroundStyle(.purple)
                .fixedSize(horizontal: false, vertical: true)
            Text(settings.startMinutes == settings.endMinutes
                 ? "Uses this device’s local time. With matching start and end times, the schedule is available whenever you listen."
                 : "Uses this device’s local time. When these hours end, check-ins stop and your station continues normally.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // A separate label and picker avoid horizontal compression at large text
    // sizes; retain the native time editor and the user's 12/24-hour preference.
    private func timePicker(_ title: String, selection: Binding<Date>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var checkInFrequency: some View {
        card("Ask Every", icon: "timer", explanation: "Choose how much playback you want between check-ins.") {
            VStack(spacing: 0) {
                ForEach(Self.durationPresets, id: \.self) { minutes in
                    durationRow(title: "\(minutes) minutes", minutes: minutes)
                    if minutes != Self.durationPresets.last { Divider() }
                }
            }
            Text("A soft chime plays for up to a minute while your station continues. Respond to start the next check-in cycle.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scheduleSummary: some View {
        card("Your Schedule", icon: "checkmark.circle", explanation: windowDescription) {
            Text("Check in after every \(settings.durationMinutes) minutes of playback during these hours.")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Label("Setting the regular Sleep Timer overrides this schedule for that listening session.", systemImage: "moon.zzz")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var howItWorks: some View {
        Section {
            DisclosureGroup(isExpanded: $showHowItWorks) {
                VStack(alignment: .leading, spacing: 16) {
                    explanation("Still awake?", text: "Tap Still Listening in the app or on the lock-screen notification. Play/pause on the lock screen, your headphones or CarPlay also counts as a response.")
                    explanation("Fallen asleep?", text: "Without a response, the station fades out over 30 seconds and pauses. Press play in the morning to pick up the live broadcast.")
                    explanation("Prefer a fixed cutoff?", text: "Use the regular Sleep Timer on the Player. It takes priority for that listening session without changing your saved schedule.")
                    explanation("Lock-screen prompts", text: "When you first turn this on, Wireless asks for notification permission. If notifications are off, you can still respond to the chime using playback controls or the in-app Still Listening button.")
                }.padding(.top, 12)
            } label: {
                Label("How Sleep Schedule Works", systemImage: "questionmark.circle")
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .glassCard(cornerRadius: 12)
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }

    private func explanation(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card<Content: View>(_ title: String, icon: String, explanation: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Label { Text(title) } icon: { Image(systemName: icon).foregroundStyle(.purple) }
                    .font(.headline).accessibilityAddTraits(.isHeader)
                Text(explanation).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 12)
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }

    private var windowDescription: String {
        let start = settings.startMinutes
        let end = settings.endMinutes
        if start == end { return "All day — matching start and end times keep the schedule available for 24 hours." }
        let hours = "Every day, \(timeLabel(start)) to \(timeLabel(end))"
        return start > end ? hours + " the following day." : hours + "."
    }

    private func timeLabel(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                         second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func durationRow(title: String, minutes: Int) -> some View {
        let selected = settings.durationMinutes == minutes
        return Button {
            settings.durationMinutes = minutes
        } label: {
            HStack(spacing: 12) {
                Text(title).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.purple : Color.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        // Multiple controls share a Form row. Plain styling keeps each tap
        // scoped to its own interval instead of activating the entire row.
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("sleepSchedule.duration.\(minutes)")
    }

    // MARK: - Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.enabled },
            set: { isOn in
                settings.enabled = isOn
                // Turning the schedule on is a user opt-in to its lock-screen
                // "still listening?" prompt, so request notification permission
                // now (no-op if already decided).
                if isOn { NotificationService.shared.requestPermission() }
            }
        )
    }

    private var startTimeBinding: Binding<Date> {
        minutesBinding(\.startMinutes)
    }

    private var endTimeBinding: Binding<Date> {
        minutesBinding(\.endMinutes)
    }

    /// Bridges a minutes-from-midnight Int setting to a Date for DatePicker.
    private func minutesBinding(_ keyPath: ReferenceWritableKeyPath<SleepScheduleSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = settings[keyPath: keyPath]
                return Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
                ) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings[keyPath: keyPath] = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }
        )
    }
}

// Wireless counterpart of Autohop's glassCard (EpisodeBadges.swift). Wireless
// targets iOS 26, so the material fallback is unnecessary.
private extension View {
    func glassCard(cornerRadius: CGFloat) -> some View {
        glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
