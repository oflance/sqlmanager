import SwiftUI

struct ProfileNodeEditorContainerView: View {
    @Binding var node: ConnectionNode
    let folderDestinations: [NodeEditor.FolderDestination]
    let currentParentID: UUID?
    let onMoveToParent: (UUID?) -> Void
    let onOpenConnection: () -> Void
    let onTestProfileConnection: (ConnectionNode, DatabaseCredential) async throws -> Void

    var body: some View {
        NodeEditor(
            node: $node,
            folderDestinations: folderDestinations,
            currentParentID: currentParentID,
            onMoveToParent: onMoveToParent,
            onOpenConnection: onOpenConnection,
            onTestConnection: {
                let credential: DatabaseCredential
                if let password = PasswordKeychain.loadPassword(forProfileID: node.id),
                   password.isEmpty == false
                {
                    credential = .password(password)
                } else {
                    credential = .none
                }

                try await onTestProfileConnection(node, credential)
            }
        )
    }
}
