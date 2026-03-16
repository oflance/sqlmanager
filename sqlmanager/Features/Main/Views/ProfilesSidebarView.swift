import SwiftUI

struct ProfilesSidebarView: View {
    let tree: [ConnectionNode]
    @Binding var selectedNodeID: UUID?
    let showColoredIcons: Bool
    let compactSidebar: Bool
    let onAddFolder: (UUID?) -> Void
    let onAddProfile: (UUID?) -> Void
    let onOpenInTab: (ConnectionNode) -> Void
    let onDeleteNode: (UUID) -> Void
    let onOpenSettings: () -> Void
    let t: (String) -> String

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedNodeID) {
                OutlineGroup(tree, children: \.childNodes) { node in
                    HStack(spacing: 8) {
                        Image(systemName: node.icon)
                            .foregroundStyle(showColoredIcons ? node.color.swiftUIColor : .primary)
                        Text(node.name)
                    }
                        .tag(node.id)
                        .contextMenu {
                            Button {
                                selectedNodeID = node.id
                                onAddFolder(node.id)
                            } label: {
                                Label(t("action.add_folder"), systemImage: "folder.badge.plus")
                            }

                            Button {
                                selectedNodeID = node.id
                                onAddProfile(node.id)
                            } label: {
                                Label(t("action.add_profile"), systemImage: "plus.rectangle.on.folder")
                            }

                            if node.kind == .profile {
                                Button {
                                    selectedNodeID = node.id
                                    onOpenInTab(node)
                                } label: {
                                    Label(t("action.open_in_tab"), systemImage: "arrow.up.right.square")
                                }
                            }

                            Divider()

                            Button(role: .destructive) {
                                onDeleteNode(node.id)
                            } label: {
                                Label(t("action.delete"), systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, compactSidebar ? 22 : 28)

            Divider()

            Button(action: onOpenSettings) {
                Label(t("action.settings"), systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(15)
        }
        .frame(minWidth: compactSidebar ? 200 : 260)
    }
}
