import SwiftUI

struct OpenedHubView: View {
    let openTabs: [ConnectionTab]
    let appLanguage: AppLanguage
    let onCloseSheet: () -> Void
    let onCloseTab: (UUID) -> Void
    let onOpenTab: (UUID) -> Void
    let onToggleConnection: (UUID) -> Void
    let t: (String) -> String

    var body: some View {
        NavigationStack {
            Group {
                if openTabs.isEmpty {
                    ContentUnavailableView(
                        t("empty.no_opened_connections"),
                        systemImage: "square.grid.2x2",
                        description: Text(t("empty.open_profile_card"))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                        ForEach(openTabs) { tab in
                            connectionCard(for: tab)
                        }
                    }
                    .padding()
                }
            }
            }
            .navigationTitle(t("action.opened_connections"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("action.close"), action: onCloseSheet)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private func connectionCard(for tab: ConnectionTab) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(tab.status.color)
                        .frame(width: 9, height: 9)
                    Text(tab.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    onCloseTab(tab.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(tab.previewText(language: appLanguage))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button(t("action.open_tab")) {
                    onOpenTab(tab.id)
                }
                .buttonStyle(.borderedProminent)

                Button(connectButtonTitle(for: tab.status)) {
                    onToggleConnection(tab.id)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func connectButtonTitle(for status: ConnectionStatus) -> String {
        switch status {
        case .connected, .connecting:
            return t("action.disconnect")
        case .disconnected:
            return t("action.connect")
        }
    }
}
