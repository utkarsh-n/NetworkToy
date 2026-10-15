import SwiftUI
import LabKitFeedback

struct BellArchiveSheet: View {
    @Binding var isEasterEggActive: Bool
    let haptics: HapticEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 18) {
                        BellStripeMark().fill(Color(NetTheme.signalBlue)).frame(width: 56, height: 56)
                            .shadow(color: NetTheme.globe.opacity(0.45), radius: 8)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("BELL LABS / ARCHIVE MEMO")
                                .font(.system(.caption2, design: .monospaced).weight(.semibold)).tracking(1)
                                .foregroundStyle(Color(NetTheme.signalBlue))
                            Text(BellArchive.title).font(.title2.weight(.bold))
                                .accessibilityIdentifier("bellLabsMemo")
                            Text(BellArchive.subtitle).font(.subheadline).foregroundStyle(NetTheme.paperMuted)
                        }
                    }
                    Text(BellArchive.stamp).font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Color(NetTheme.signalBlue))
                        .padding(10).overlay(Rectangle().stroke(Color(NetTheme.signalBlue).opacity(0.6), lineWidth: 1))
                    Text(BellArchive.intro).font(.body)
                    Text(BellArchive.retained).font(.subheadline).foregroundStyle(NetTheme.paperMuted)
                    Toggle(isOn: $isEasterEggActive) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Let the Baby Bells out").font(.headline)
                            Text("Seven satellites. Zero changes to your network.")
                                .font(.caption).foregroundStyle(NetTheme.paperMuted)
                        }
                    }
                    .tint(Color(NetTheme.signature))
                    .padding(14).background(NetTheme.paperPanel, in: .rect(cornerRadius: 8))
                    .accessibilityIdentifier("babyBellToggle")
                    .onChange(of: isEasterEggActive) { _, _ in haptics.play(.switchClick) }
                    HStack {
                        Text("THE NEW DIRECTORY").font(.system(.caption2, design: .monospaced).weight(.bold)).tracking(1)
                        Spacer()
                        Text("7 regional companies").font(.caption)
                            .accessibilityIdentifier("babyBellCount")
                    }.foregroundStyle(NetTheme.paperMuted)
                    VStack(spacing: 0) {
                        ForEach(Array(BellArchive.items.enumerated()), id: \.element.id) { index, bell in
                            HStack(alignment: .top, spacing: 14) {
                                VStack(spacing: 7) {
                                    Image(systemName: "bell.fill").font(.body).foregroundStyle(Color(NetTheme.signalBlue))
                                    Text(String(format: "%02d", index + 1))
                                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(NetTheme.paperMuted)
                                }.frame(width: 28).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(bell.name).font(.headline)
                                    Text(bell.region).font(.caption).foregroundStyle(NetTheme.paperMuted)
                                    Text(bell.quip).font(.subheadline).italic().foregroundStyle(NetTheme.ink.opacity(0.85))
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.vertical, 14)
                            if index < BellArchive.items.count - 1 { Divider().overlay(NetTheme.ink.opacity(0.10)) }
                        }
                    }
                    Text("Memo footnote: the jokes are ours. The seven companies are historical.")
                        .font(.caption).foregroundStyle(NetTheme.paperMuted)
                    Text(BellArchive.modernModelNote).font(.subheadline)
                        .padding(14).background(NetTheme.paperPanel, in: .rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ARCHIVE REFERENCES").font(.system(.caption2, design: .monospaced)).tracking(1)
                            .foregroundStyle(NetTheme.paperMuted)
                        ForEach(BellArchive.sources) { source in
                            if let url = URL(string: source.url) {
                                Link(destination: url) {
                                    Label(source.title, systemImage: "arrow.up.right")
                                        .font(.subheadline).frame(minHeight: 44, alignment: .leading)
                                }
                            }
                        }
                    }
                }.foregroundStyle(NetTheme.ink).padding(24)
            }
            .background(NetTheme.paper)
            .navigationTitle("1984 archive").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NetTheme.paper, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("bellLabsMemoDone")
                }
            }
        }
        .tint(Color(NetTheme.signalBlue))
        .preferredColorScheme(.dark)
    }
}
