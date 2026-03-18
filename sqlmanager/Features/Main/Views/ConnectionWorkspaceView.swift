import SwiftUI

struct ConnectionWorkspaceView: View {
    let tab: ConnectionTab
    let appLanguage: AppLanguage
    let runQueryShortcut: Bool
    let diagnosticMessage: String?
    let querySummary: String?
    let schemaLoading: Bool
    let schemaObjects: [SchemaObject]
    let selectedSchemaPath: String?
    let queryResult: QueryExecutionResult?
    let suggestions: [String]
    let t: (String) -> String

    @Binding var queryText: String

    let onClose: () -> Void
    let onToggleConnection: () -> Void
    let onTestTCP: () -> Void
    let onRunQuery: () -> Void
    let onRefreshSchema: () -> Void
    let onSelectSchemaObject: (String) -> Void
    let onPreviewRows: (String) -> Void
    let onApplySuggestion: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(tab.title)
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: onClose) {
                    Label(t("action.close"), systemImage: "xmark")
                }
            }

            Text(tab.status.localized(language: appLanguage))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tab.status.color.opacity(0.15))
                .clipShape(Capsule())

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("\(t("field.database")):")
                        .foregroundStyle(.secondary)
                    Text(tab.databaseType.localized(language: appLanguage))
                }
                GridRow {
                    Text("\(t("field.method")):")
                        .foregroundStyle(.secondary)
                    Text(tab.connectionMethod.localized(language: appLanguage))
                }
                GridRow {
                    Text("\(t("field.ssl")):")
                        .foregroundStyle(.secondary)
                    Text(tab.useSSL ? t("value.enabled") : t("value.disabled"))
                }
                GridRow {
                    Text("\(t("field.timeout")):")
                        .foregroundStyle(.secondary)
                    Text("\(tab.timeoutSeconds)s")
                }
            }

            HStack(spacing: 10) {
                Button(connectButtonTitle(for: tab.status), action: onToggleConnection)
                    .buttonStyle(.borderedProminent)

                Button(t("action.test_tcp"), action: onTestTCP)
                    .buttonStyle(.bordered)
                    .disabled(tab.status == .connecting)

                if runQueryShortcut {
                    Button(t("action.run_query"), action: onRunQuery)
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(tab.status != .connected)
                } else {
                    Button(t("action.run_query"), action: onRunQuery)
                        .buttonStyle(.bordered)
                        .disabled(tab.status != .connected)
                }
            }

            if let diagnosticMessage, diagnosticMessage.isEmpty == false {
                Text(diagnosticMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let querySummary, querySummary.isEmpty == false {
                Text(querySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HSplitView {
                schemaBrowserPane
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
                queryWorkspacePane
            }
            .frame(minHeight: 420)

            Spacer()
        }
        .padding()
    }

    private var schemaBrowserPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(t("schema.browser.title"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(t("action.refresh_schema"), action: onRefreshSchema)
                    .buttonStyle(.bordered)
                    .disabled(tab.status != .connected || schemaLoading)
            }

            if schemaLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(t("status.loading_schema"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if schemaObjects.isEmpty {
                Text(t("schema.browser.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(schemaObjects) { object in
                            Button {
                                onSelectSchemaObject(object.path)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: object.kind == .view ? "eye" : "tablecells")
                                        .foregroundStyle(.secondary)
                                    Text(object.path)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill((selectedSchemaPath == object.path) ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let selectedSchemaPath, selectedSchemaPath.isEmpty == false {
                HStack {
                    Text(selectedSchemaPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(t("action.preview_rows")) {
                        onPreviewRows(selectedSchemaPath)
                    }
                    .buttonStyle(.bordered)
                    .disabled(tab.status != .connected)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var queryWorkspacePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            queryResultsPane
                .frame(minHeight: 220, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text(t("query.editor.title"))
                    .font(.subheadline.weight(.semibold))

                TextEditor(text: $queryText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if suggestions.isEmpty == false {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    onApplySuggestion(suggestion)
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }

    private var queryResultsPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("query.results.title"))
                .font(.subheadline.weight(.semibold))

            if let queryResult, queryResult.columns.isEmpty == false {
                let rows = Array(queryResult.rows.prefix(200))
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(queryResult.columns.indices, id: \.self) { columnIndex in
                                Text(queryResult.columns[columnIndex].name)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .frame(minWidth: 150, alignment: .leading)
                                    .background(Color.secondary.opacity(0.14))
                            }
                        }

                        ForEach(rows.indices, id: \.self) { rowIndex in
                            HStack(spacing: 0) {
                                ForEach(queryResult.columns.indices, id: \.self) { columnIndex in
                                    let cellValue = columnIndex < rows[rowIndex].count ? rows[rowIndex][columnIndex] : .null
                                    Text(stringValue(for: cellValue))
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .frame(minWidth: 150, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                            .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.05))
                        }
                    }
                }
                .background(Color.secondary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(t("query.results.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 6)
            }
        }
    }

    private func connectButtonTitle(for status: ConnectionStatus) -> String {
        switch status {
        case .connected, .connecting:
            return t("action.disconnect")
        case .disconnected:
            return t("action.connect")
        }
    }

    private func stringValue(for value: DatabaseValue) -> String {
        switch value {
        case .null:
            return "NULL"
        case .integer(let number):
            return String(number)
        case .double(let number):
            return String(number)
        case .string(let text):
            return text
        case .bool(let flag):
            return flag ? "true" : "false"
        case .date(let date):
            return isoDateFormatter.string(from: date)
        case .binary(let data):
            return "<\(data.count) bytes>"
        }
    }

    private var isoDateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
