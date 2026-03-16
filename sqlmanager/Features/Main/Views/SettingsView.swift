import SwiftUI

struct SettingsView: View {
    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case appearance
        case behavior
        case connections

        var id: String { rawValue }
    }

    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue
    @AppStorage("appTheme") private var appThemeRaw = AppTheme.auto.rawValue
    @AppStorage("settingsAccentColor") private var accentColorRaw = AppAccent.system.rawValue
    @AppStorage("settingsShowColoredIcons") private var showColoredIcons = true
    @AppStorage("settingsCompactSidebar") private var compactSidebar = false
    @AppStorage("settingsConfirmDelete") private var confirmDelete = true
    @AppStorage("settingsShowWelcome") private var showWelcomeOnStart = true
    @AppStorage("settingsAutoConnect") private var autoConnect = false
    @AppStorage("settingsRunQueryShortcut") private var runQueryShortcut = true
    @AppStorage("settingsUseSSL") private var useSSL = true
    @AppStorage("settingsTimeoutSeconds") private var timeoutSeconds = 15
    @State private var selectedTab: SettingsTab = .general

    let t: (String) -> String

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tag(SettingsTab.general)
                .tabItem { Label(t("settings.tab.general"), systemImage: "slider.horizontal.3") }

            appearanceTab
                .tag(SettingsTab.appearance)
                .tabItem { Label(t("settings.tab.appearance"), systemImage: "paintbrush") }

            behaviorTab
                .tag(SettingsTab.behavior)
                .tabItem { Label(t("settings.tab.behavior"), systemImage: "cursorarrow.motionlines") }

            connectionsTab
                .tag(SettingsTab.connections)
                .tabItem { Label(t("settings.tab.connections"), systemImage: "network") }
        }
        .navigationTitle(t("action.settings"))
    }

    private var generalTab: some View {
        Form {
            Section(t("settings.language.section")) {
                Picker(t("settings.language"), selection: $appLanguageRaw) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(languageDisplayName(language))
                            .tag(language.rawValue)
                    }
                }
            }
            Section(t("settings.startup.section")) {
                Toggle(t("settings.show_welcome"), isOn: $showWelcomeOnStart)
            }
        }
    }

    private var appearanceTab: some View {
        Form {
            Section(t("settings.appearance")) {
                Picker(t("settings.theme"), selection: $appThemeRaw) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(themeDisplayName(theme))
                            .tag(theme.rawValue)
                    }
                }
                Picker(t("settings.accent_color"), selection: $accentColorRaw) {
                    ForEach(AppAccent.allCases) { accent in
                        Text(accentDisplayName(accent))
                            .tag(accent.rawValue)
                    }
                }
                Toggle(t("settings.show_colored_icons"), isOn: $showColoredIcons)
                Toggle(t("settings.compact_sidebar"), isOn: $compactSidebar)
            }
        }
    }

    private var behaviorTab: some View {
        Form {
            Section(t("settings.behavior.section")) {
                Toggle(t("settings.confirm_delete"), isOn: $confirmDelete)
                Toggle(t("settings.auto_connect_profile"), isOn: $autoConnect)
                Toggle(t("settings.run_query_shortcut"), isOn: $runQueryShortcut)
            }
        }
    }

    private var connectionsTab: some View {
        Form {
            Section(t("settings.connections")) {
                Toggle(t("settings.use_ssl"), isOn: $useSSL)
                Stepper(
                    "\(t("settings.timeout_seconds")): \(timeoutSeconds)s",
                    value: $timeoutSeconds,
                    in: 5...120,
                    step: 5
                )
            }
            Section(t("settings.info.section")) {
                Text(t("settings.drivers_coming"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func languageDisplayName(_ language: AppLanguage) -> String {
        if language == .system {
            return t("lang.system")
        }
        return language.displayName
    }

    private func themeDisplayName(_ theme: AppTheme) -> String {
        switch theme {
        case .auto:
            return t("settings.theme.auto")
        case .light:
            return t("settings.theme.light")
        case .dark:
            return t("settings.theme.dark")
        }
    }

    private func accentDisplayName(_ accent: AppAccent) -> String {
        switch accent {
        case .system:
            return t("settings.accent.system")
        case .blue:
            return t("settings.accent.blue")
        case .green:
            return t("settings.accent.green")
        case .orange:
            return t("settings.accent.orange")
        case .red:
            return t("settings.accent.red")
        case .pink:
            return t("settings.accent.pink")
        case .indigo:
            return t("settings.accent.indigo")
        }
    }
}
