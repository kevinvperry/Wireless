import SwiftUI

// Adapted from Autohop's SleepTimerSheetView for continuous live radio.
struct SleepTimerSheetView: View {
    @ObservedObject var sleepTimer: SleepTimerService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(white: 0.3))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                if sleepTimer.isActive {
                    activeTimerView
                } else {
                    inactiveView
                }

                Spacer(minLength: 20)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .presentationBackground(.regularMaterial)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
    }

    private var inactiveView: some View {
        VStack(spacing: 0) {
            sectionHeader

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                presetButton("5 min", seconds: 5 * 60)
                presetButton("10 min", seconds: 10 * 60)
                presetButton("15 min", seconds: 15 * 60)
                presetButton("30 min", seconds: 30 * 60)
                presetButton("45 min", seconds: 45 * 60)
                presetButton("1 hour", seconds: 60 * 60)
            }
            .padding(.horizontal, 20)

            Text("Wireless will gradually fade the station during the final 30 seconds, then pause playback.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }

    private func presetButton(_ label: String, seconds: TimeInterval) -> some View {
        Button {
            sleepTimer.start(seconds: seconds)
            dismiss()
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set sleep timer for \(label)")
    }

    private var activeTimerView: some View {
        VStack(spacing: 24) {
            sectionHeader

            Text(formattedTimeRemaining)
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .accessibilityIdentifier("sleepTimerCountdown")

            HStack(spacing: 12) {
                Button("+5 min") { sleepTimer.extend(by: 5) }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                Button("Cancel") { sleepTimer.cancel() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 20)
    }

    private var sectionHeader: some View {
        Text("Sleep Timer")
            .font(.system(size: 13, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(Color(white: 0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
    }

    private var formattedTimeRemaining: String {
        let total = max(0, Int(sleepTimer.timeRemaining))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
