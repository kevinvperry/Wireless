import SwiftUI

/// Adapted from Autohop's drill-down Support page.
struct WirelessSupportView: View {
    var body: some View {
        List {
            Section {
                ForEach(WirelessSupportGuide.sections) { section in
                    NavigationLink {
                        WirelessSupportSectionView(section: section)
                    } label: {
                        WirelessSupportSectionRow(section: section)
                    }
                }
            } footer: {
                Text("Tap a topic to read the full guide.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .tint(.purple)
        .accessibilityIdentifier("supportGuide")
    }
}

private struct WirelessSupportSectionRow: View {
    let section: WirelessSupportSection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 42, height: 42)
                .background(Color.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(section.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct WirelessSupportSectionView: View {
    let section: WirelessSupportSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: section.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.purple)
                        .frame(width: 44, height: 44)
                        .background(Color.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
                    Text(section.title).font(.system(size: 26, weight: .bold))
                }
                .padding(.bottom, 4)

                ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                    WirelessSupportBlockView(block: block)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .tint(.purple)
    }
}

private struct WirelessSupportBlockView: View {
    let block: WirelessSupportBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            WirelessSupportText(text)
                .font(.system(size: 15)).foregroundStyle(Color(white: 0.75)).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .heading(let text):
            Text(text).font(.system(size: 17, weight: .bold)).padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("–").font(.system(size: 15, weight: .bold)).foregroundStyle(.purple)
                        WirelessSupportText(item).font(.system(size: 15)).foregroundStyle(Color(white: 0.75))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .steps(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1).").font(.system(size: 14, weight: .bold)).foregroundStyle(.purple).monospacedDigit()
                        WirelessSupportText(item).font(.system(size: 15)).foregroundStyle(Color(white: 0.75))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .callout(let style, let text):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: style.symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(style.tint)
                WirelessSupportText(text).font(.system(size: 14)).foregroundStyle(Color(white: 0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(style.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(style.tint.opacity(0.3), lineWidth: 0.5))
        case .table(let rows):
            VStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 6) {
                        WirelessSupportText(row.first ?? "").font(.system(size: 15, weight: .semibold))
                        ForEach(Array(row.dropFirst().enumerated()), id: \.offset) { _, cell in
                            WirelessSupportText(cell).font(.system(size: 14)).foregroundStyle(Color(white: 0.72))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                }
            }
        }
    }
}

private struct WirelessSupportText: View {
    private let attributed: AttributedString

    init(_ string: String) {
        attributed = (try? AttributedString(markdown: string, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(string)
    }

    var body: some View { Text(attributed) }
}
