import SwiftUI

/// Adapted from Autohop's Views/AcknowledgementsView.swift ("Acknowledgements"
/// page, Settings → About). Static open-source credits list. The Pocket Casts
/// for iOS (Automattic, MPL-2.0) notice must stay consistent with NOTICE and
/// LICENSE-MPL-2.0.md.
struct AcknowledgementsView: View {
    private var cardBackground: Color { Color.white.opacity(0.05) }

    var body: some View {
        List {
            Section {
                AcknowledgementRow(
                    name: "Wireless",
                    author: "Kevin Perry",
                    licence: "MIT",
                    licenceURL: URL(string: "https://github.com/kevinvperry/Wireless/blob/main/LICENSE"),
                    repoURL: URL(string: "https://github.com/kevinvperry/Wireless"),
                    description: "Wireless's original code and documentation are available under the MIT Licence. The shared Vocal Boost and music processing code retains the MPL-2.0 licence described below. Broadcaster names, artwork and audio retain their owners' rights."
                )
            } header: {
                Text("Project Licence")
            }
            .listRowBackground(cardBackground)

            Section {
                AcknowledgementRow(
                    name: "Pocket Casts for iOS",
                    author: "Automattic, Inc.",
                    licence: "MPL-2.0",
                    licenceURL: URL(string: "https://mozilla.org/MPL/2.0/"),
                    repoURL: URL(string: "https://github.com/Automattic/pocket-casts-ios"),
                    description: "The Vocal Boost signal chain used in Wireless's audio engine (high-pass filter, dynamics processing and limiter values) is adapted from Autohop's playback engine, which is based on Pocket Casts' EffectsPlayer.swift. Mid Bass, Deep Bass and Pop & R&B use the same covered processing file with Wireless-specific music presets."
                )
            } header: {
                Text("Open Source Components")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wireless uses portions of the above open-source project. The licence text is available from the Licence link above and in the Wireless source repository.")
                    if let wirelessRepo = URL(string: "https://github.com/kevinvperry/Wireless") {
                        Text("As required by the MPL-2.0, the source code of Wireless's modified version of the covered file (VocalBoost.swift) is published here:")
                        Link(destination: wirelessRepo) {
                            Label("github.com/kevinvperry/Wireless", systemImage: "arrow.up.right.square")
                                .font(.footnote.weight(.medium))
                        }
                        .tint(.purple)
                    }
                }
                .font(.footnote)
            }
            .listRowBackground(cardBackground)
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .tint(.purple)
    }
}

// MARK: - Row

private struct AcknowledgementRow: View {
    let name: String
    let author: String
    let licence: String
    let licenceURL: URL?
    let repoURL: URL?
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.body.weight(.semibold))
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                LicenceBadge(text: licence)
            }

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                if let repoURL {
                    Link(destination: repoURL) {
                        Label("Source", systemImage: "arrow.up.right.square")
                            .font(.footnote.weight(.medium))
                    }
                }
                if let licenceURL {
                    Link(destination: licenceURL) {
                        Label("Licence", systemImage: "doc.text")
                            .font(.footnote.weight(.medium))
                    }
                }
            }
            .buttonStyle(.borderless)
            .tint(.purple)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Licence badge

private struct LicenceBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.purple.opacity(0.18), in: Capsule())
            .foregroundStyle(.purple)
    }
}
