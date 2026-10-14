import SwiftUI

struct StreamDiagnosticView: View {
    @State private var enabled = StreamDiagnosticLogger.shared.isEnabled
    @State private var lines: [String] = []
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
                Text("Records playback backends, connection changes, buffering, failover, stream URLs, stream format and TV Sync timing. Authentication values, device names and programme metadata are excluded.")
            }

            Section("Recent activity") {
                if lines.isEmpty {
                    ContentUnavailableView("No stream activity recorded", systemImage: "waveform.path.ecg")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Stream Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .tint(.purple)
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
        lines = StreamDiagnosticLogger.shared.recentLines()
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("wireless-stream-diagnostics.log")
            try StreamDiagnosticLogger.shared.writeRedactedExport(to: url)
            exportURL = url
        } catch {
            exportURL = nil
            exportError = error.localizedDescription
        }
    }
}
