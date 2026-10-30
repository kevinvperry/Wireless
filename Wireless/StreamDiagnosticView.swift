import SwiftUI

struct StreamDiagnosticView: View {
    private enum Focus: String, CaseIterable, Identifiable {
        case metadata = "Metadata"
        case playback = "Playback"
        case shazam = "Shazam"
        case all = "All"
        var id: Self { self }
    }

    @State private var enabled = StreamDiagnosticLogger.shared.isEnabled
    @State private var lines: [String] = []
    @AppStorage("streamDiagnosticFocus") private var focusRawValue = Focus.metadata.rawValue
    @State private var searchText = ""
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showClearConfirmation = false

    var body: some View {
        List {
            Section {
                Toggle("Record Stream Diagnostics", isOn: $enabled)
                    .tint(.purple)
                    .accessibilityIdentifier("streamDiagnosticsEnabled")
                    .onChange(of: enabled) { _, value in
                        StreamDiagnosticLogger.shared.isEnabled = value
                        refresh()
                    }
            } footer: {
                Text("Records playback, stream, metadata and Shazam identification details. Broadcast song titles, artists, advertisements, programme labels and technical markers are included so display issues can be diagnosed. Authentication values and device names are excluded.")
            }

            if focus != .shazam { metadataSummarySection }

            Section {
                Picker("Diagnostic focus", selection: focusBinding) {
                    ForEach(Focus.allCases) { value in Text(value.rawValue).tag(value) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("diagnosticFocus")
            }

            Section(focus == .metadata ? "Metadata activity" : "Recent activity") {
                if filteredLines.isEmpty {
                    ContentUnavailableView(searchText.isEmpty ? "No matching activity recorded" : "No search results", systemImage: "waveform.path.ecg")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(filteredLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: icon(for: line))
                                .foregroundStyle(colour(for: line))
                                .frame(width: 16)
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Stream Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .tint(.purple)
        .searchable(text: $searchText, prompt: "Search diagnostics")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                if let exportURL {
                    ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }
                }
                Button("Clear", systemImage: "trash", role: .destructive) {
                    showClearConfirmation = true
                }
                .disabled(lines.isEmpty)
            }
        }
        .confirmationDialog("Clear stream diagnostic log?", isPresented: $showClearConfirmation) {
            Button("Delete Log History", role: .destructive) {
                StreamDiagnosticLogger.shared.clear()
                refresh()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Could not prepare diagnostic export", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .task { refresh() }
    }

    private func refresh() {
        lines = StreamDiagnosticLogger.shared.recentLines(limit: 2000)
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("wireless-stream-diagnostics.log")
            try StreamDiagnosticLogger.shared.writeRedactedExport(to: url)
            exportURL = url
        } catch {
            exportURL = nil
            exportError = error.localizedDescription
        }
    }

    private var metadataSummarySection: some View {
        Section {
            diagnosticCountRow("Received and evaluated", value: metadataEvaluatedCountText)
            diagnosticCountRow("Displayed", value: metadataDisplayedCountText)
            diagnosticCountRow("Rejected or cleared", value: rejectedMetadataCountText)
            diagnosticCountRow("Provider heartbeats", value: metadataHeartbeatCountText)
            diagnosticCountRow("Silence warnings", value: metadataSilenceCountText)
            diagnosticCountRow("Stale values cleared", value: metadataStaleCountText)
            diagnosticCountRow("Provider failures", value: metadataProviderFailureCountText)
        } header: {
            Text("Metadata summary")
        } footer: {
            Text("Classification hints identify likely advertisements, programme labels and technical markers. Heartbeats confirm that a provider is still responding; silence warnings mean no usable metadata has been received for the configured period. Stale values are cleared when their embedded timestamp or unchanged display age exceeds the freshness limit.")
        }
    }

    private func diagnosticCountRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private var filteredLines: [String] {
        lines.filter { line in
            let matchesFocus = switch focus {
            case .metadata: line.contains(" metadata.")
            case .playback: !line.contains(" metadata.") && !line.contains(" recognition.")
            case .shazam: line.contains(" recognition.")
            case .all: true
            }
            return matchesFocus && (searchText.isEmpty || line.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var focus: Focus {
        Focus(rawValue: focusRawValue) ?? .metadata
    }

    private var focusBinding: Binding<Focus> {
        Binding(
            get: { focus },
            set: { focusRawValue = $0.rawValue }
        )
    }

    private func metadataCount(_ event: String) -> Int {
        lines.count { $0.contains(" \(event) ") }
    }

    private var metadataEvaluatedCountText: String { String(metadataCount("metadata.evaluated")) }
    private var metadataDisplayedCountText: String { String(metadataCount("metadata.displayed")) }
    private var rejectedMetadataCountText: String { String(rejectedMetadataCount) }
    private var metadataHeartbeatCountText: String { String(metadataCount("metadata.providerHeartbeat")) }
    private var metadataSilenceCountText: String { String(metadataCount("metadata.silence")) }
    private var metadataStaleCountText: String { String(metadataCount("metadata.stale")) }
    private var metadataProviderFailureCountText: String { String(metadataCount("metadata.providerFailed")) }

    private var rejectedMetadataCount: Int {
        lines.count {
            ($0.contains(" metadata.evaluated ") && $0.contains("outcome=\"rejected."))
                || $0.contains(" metadata.displayCleared ")
        }
    }

    private func icon(for line: String) -> String {
        if line.contains("recognition.") {
            return line.contains("failed") || line.contains("timeout") || line.contains("rejected") ? "exclamationmark.triangle.fill" : "shazam.logo"
        }
        if line.contains("providerFailed") || line.contains("metadata.silence") || line.contains("metadata.stale") || line.contains("rejected.") { return "exclamationmark.triangle.fill" }
        if line.contains("displayed") || line.contains("providerRecovered") || line.contains("providerHeartbeat") { return "checkmark.circle.fill" }
        if line.contains("displayCleared") || line.contains("providerStopped") { return "minus.circle.fill" }
        return "waveform.badge.magnifyingglass"
    }

    private func colour(for line: String) -> Color {
        if line.contains("recognition.") { return line.contains("failed") || line.contains("timeout") || line.contains("rejected") ? .orange : .purple }
        if line.contains("providerFailed") || line.contains("metadata.silence") || line.contains("metadata.stale") || line.contains("rejected.") { return .orange }
        if line.contains("displayed") || line.contains("providerRecovered") || line.contains("providerHeartbeat") { return .green }
        return .secondary
    }
}
