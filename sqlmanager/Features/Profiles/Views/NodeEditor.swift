//
//  NodeEditor.swift
//  sqlmanager
//

import SwiftUI

struct NodeEditor: View {
    struct FolderDestination: Identifiable {
        let id = UUID()
        let parentID: UUID?
        let title: String
    }

    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue
    @Binding var node: ConnectionNode
    @State private var passwordDraft = ""
    @State private var isSyncingPassword = false
    @State private var isTestingConnection = false
    @State private var connectionTestMessage: String?
    @State private var connectionTestSucceeded = false
    let folderDestinations: [FolderDestination]
    let currentParentID: UUID?
    let onMoveToParent: (UUID?) -> Void
    let onOpenConnection: () -> Void
    let onTestConnection: () async throws -> Void

    private let iconOptions = [
        "folder", "folder.fill", "server.rack", "cylinder", "externaldrive.connected.to.line.below", "network", "bolt.horizontal.circle"
    ]

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    private func t(_ key: String) -> String {
        L10n.tr(key, language: appLanguage)
    }

    var body: some View {
        Form {
            Section(t("form.general")) {
                TextField(t("field.name"), text: $node.name)

                LabeledContent(t("field.icon")) {
                    HStack(spacing: 10) {
                        ForEach(iconOptions, id: \.self) { icon in
                            let isSelected = node.icon == icon
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    node.icon = icon
                                }
                            } label: {
                                Circle()
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Image(systemName: icon)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.primary)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(isSelected ? Color.black.opacity(0.9) : Color.secondary.opacity(0.35), lineWidth: isSelected ? 2 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(icon)
                        }
                    }
                }

                LabeledContent(t("field.color")) {
                    HStack(spacing: 10) {
                        ForEach(NodeColor.allCases) { color in
                            let isSelected = node.color == color
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    node.color = color
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(color == .defaultColor ? Color(NSColor.controlBackgroundColor) : color.swiftUIColor)
                                        .frame(width: 14, height: 14)

                                    if color == .defaultColor {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 7, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.85), lineWidth: isSelected ? 1.5 : 0)
                                        .padding(2)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? Color.black.opacity(0.9) : Color.secondary.opacity(0.35), lineWidth: isSelected ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .help(color.localized(language: appLanguage))
                        }
                    }
                }

                if folderDestinations.isEmpty == false {
                    LabeledContent(t("action.move_to_folder")) {
                        Picker("", selection: moveParentBinding) {
                            ForEach(folderDestinations) { destination in
                                Text(destination.title)
                                    .tag(destination.parentID)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220, alignment: .trailing)
                    }
                }
            }

            if node.kind == .profile {
                Section(t("form.connection")) {
                    Picker(t("field.database_type"), selection: $node.databaseType) {
                        ForEach(DatabaseType.allCases) { type in
                            Text(type.localized(language: appLanguage)).tag(type)
                        }
                    }

                    Picker(t("field.method"), selection: $node.connectionMethod) {
                        ForEach(ConnectionMethod.allCases) { method in
                            Text(method.localized(language: appLanguage)).tag(method)
                        }
                    }

                    TextField(t("field.host"), text: $node.host)
                    TextField(t("field.port"), text: $node.port)
                    TextField(t("field.database"), text: $node.database)
                    TextField(t("field.username"), text: $node.username)
                    SecureField(t("field.password"), text: $passwordDraft)
                    Toggle(t("settings.use_ssl"), isOn: $node.useSSL)
                    Stepper(
                        "\(t("settings.timeout_seconds")): \(node.timeoutSeconds)s",
                        value: $node.timeoutSeconds,
                        in: 5...120,
                        step: 5
                    )
                }

                Section {
                    Button(t("action.test_connection")) {
                        runConnectionTest()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingConnection)

                    Button(t("action.open_in_tab")) {
                        onOpenConnection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTestingConnection)

                    if let connectionTestMessage, connectionTestMessage.isEmpty == false {
                        Text(connectionTestMessage)
                            .font(.caption)
                            .foregroundStyle(connectionTestSucceeded ? .green : .secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            syncPasswordFromKeychain()
        }
        .onChange(of: node.id) { _, _ in
            syncPasswordFromKeychain()
        }
        .onChange(of: passwordDraft) { _, newValue in
            guard isSyncingPassword == false else { return }
            if newValue.isEmpty {
                _ = PasswordKeychain.deletePassword(forProfileID: node.id)
            } else {
                _ = PasswordKeychain.save(password: newValue, forProfileID: node.id)
            }
        }
        .onChange(of: node.host) { _, _ in connectionTestMessage = nil }
        .onChange(of: node.port) { _, _ in connectionTestMessage = nil }
        .onChange(of: node.database) { _, _ in connectionTestMessage = nil }
        .onChange(of: node.username) { _, _ in connectionTestMessage = nil }
        .onChange(of: node.databaseType) { _, _ in connectionTestMessage = nil }
        .onChange(of: node.connectionMethod) { _, _ in connectionTestMessage = nil }
        .onChange(of: node.useSSL) { _, _ in connectionTestMessage = nil }
        .onChange(of: passwordDraft) { _, _ in connectionTestMessage = nil }
    }

    private var moveParentBinding: Binding<UUID?> {
        Binding(
            get: { currentParentID },
            set: { newValue in
                if newValue != currentParentID {
                    onMoveToParent(newValue)
                }
            }
        )
    }

    private func syncPasswordFromKeychain() {
        isSyncingPassword = true
        passwordDraft = PasswordKeychain.loadPassword(forProfileID: node.id) ?? ""
        isSyncingPassword = false
    }

    private func runConnectionTest() {
        isTestingConnection = true
        connectionTestSucceeded = false
        connectionTestMessage = t("status.testing_connection")

        Task {
            do {
                try await onTestConnection()
                connectionTestSucceeded = true
                connectionTestMessage = t("status.connection_ok")
            } catch {
                connectionTestSucceeded = false
                connectionTestMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isTestingConnection = false
        }
    }
}
