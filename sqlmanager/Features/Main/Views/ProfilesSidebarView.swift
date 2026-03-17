import SwiftUI

struct ProfilesSidebarView: View {
    private struct SearchRow: Identifiable {
        let node: ConnectionNode
        let depth: Int
        var id: UUID { node.id }
    }

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
    @State private var filterText = ""

    private var isSearching: Bool {
        filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var filteredTree: [ConnectionNode] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return tree }
        return tree.compactMap { node in
            filter(node: node, query: query)
        }
    }

    private var expandedSearchRows: [SearchRow] {
        flatten(nodes: filteredTree, depth: 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedNodeID) {
                if isSearching {
                    ForEach(expandedSearchRows) { row in
                        nodeRow(row.node, depth: row.depth)
                    }
                } else {
                    OutlineGroup(tree, children: \.childNodes) { node in
                        nodeRow(node, depth: 0)
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, compactSidebar ? 22 : 28)

            Divider()

            HStack(spacing: 8) {
                ZStack(alignment: .trailing) {
                    TextField(t("placeholder.sidebar_filter"), text: $filterText)
                        .textFieldStyle(.roundedBorder)
                        .padding(.trailing, filterText.isEmpty ? 0 : 22)

                    if filterText.isEmpty == false {
                        Button {
                            filterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }
                }

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(t("action.settings"))
            }
            .padding(12)
        }
        .frame(minWidth: compactSidebar ? 200 : 260)
    }

    private func nodeRow(_ node: ConnectionNode, depth: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: node.icon)
                .foregroundStyle(showColoredIcons ? node.color.swiftUIColor : .primary)
            Text(node.name)
        }
        .padding(.leading, isSearching ? CGFloat(depth) * 14 : 0)
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

    private func filter(node: ConnectionNode, query: String) -> ConnectionNode? {
        let matchingChildren = node.children.compactMap { child in
            filter(node: child, query: query)
        }

        if node.name.localizedCaseInsensitiveContains(query) {
            var result = node
            result.children = matchingChildren
            return result
        }

        if matchingChildren.isEmpty == false {
            var result = node
            result.children = matchingChildren
            return result
        }

        return nil
    }

    private func flatten(nodes: [ConnectionNode], depth: Int) -> [SearchRow] {
        nodes.flatMap { node in
            [SearchRow(node: node, depth: depth)] + flatten(nodes: node.children, depth: depth + 1)
        }
    }
}
