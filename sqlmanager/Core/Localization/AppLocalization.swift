//
//  AppLocalization.swift
//  sqlmanager
//

import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case ua
    case ru
    case de

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .ua: return "Українська"
        case .ru: return "Русский"
        case .de: return "Deutsch"
        }
    }

    static func resolved(selected: AppLanguage, locale: Locale = .current) -> AppLanguage {
        guard selected == .system else { return selected }
        let id = locale.identifier.lowercased()
        if id.hasPrefix("uk") || id.hasPrefix("ua") { return .ua }
        if id.hasPrefix("ru") { return .ru }
        if id.hasPrefix("de") { return .de }
        return .en
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum AppAccent: String, CaseIterable, Identifiable {
    case system
    case blue
    case green
    case orange
    case red
    case pink
    case indigo

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .system:
            return .accentColor
        case .blue:
            return .blue
        case .green:
            return .green
        case .orange:
            return .orange
        case .red:
            return .red
        case .pink:
            return .pink
        case .indigo:
            return .indigo
        }
    }
}

enum L10n {
    static func tr(_ key: String, language: AppLanguage, locale: Locale = .current) -> String {
        let activeLanguage = AppLanguage.resolved(selected: language, locale: locale)
        return table[key]?[activeLanguage] ?? table[key]?[.en] ?? key
    }

    private static let table: [String: [AppLanguage: String]] = [
        "nav.profiles": [.en: "Profiles", .ua: "Профілі", .ru: "Профили", .de: "Profile"],
        "action.add_folder": [.en: "Add Folder", .ua: "Додати папку", .ru: "Добавить папку", .de: "Ordner hinzufügen"],
        "action.add_profile": [.en: "Add Profile", .ua: "Додати профіль", .ru: "Добавить профиль", .de: "Profil hinzufügen"],
        "placeholder.sidebar_filter": [.en: "Filter profiles and folders", .ua: "Фільтр профілів і папок", .ru: "Фильтр профилей и папок", .de: "Profile und Ordner filtern"],
        "action.delete": [.en: "Delete", .ua: "Видалити", .ru: "Удалить", .de: "Löschen"],
        "action.opened_connections": [.en: "Opened Connections", .ua: "Відкриті підключення", .ru: "Открытые подключения", .de: "Geöffnete Verbindungen"],
        "action.settings": [.en: "Settings", .ua: "Налаштування", .ru: "Настройки", .de: "Einstellungen"],
        "action.move_to_folder": [.en: "Move To Folder", .ua: "Перемістити в папку", .ru: "Переместить в папку", .de: "In Ordner verschieben"],
        "action.move_to_root": [.en: "Move To Root", .ua: "Перемістити в корінь", .ru: "Переместить в корень", .de: "In Stamm verschieben"],
        "action.drop_to_root": [.en: "Drop To Root", .ua: "Перемістити в корінь", .ru: "Переместить в корень", .de: "In Stamm verschieben"],
        "empty.select_profile_or_folder": [.en: "Select Profile or Folder", .ua: "Оберіть профіль або папку", .ru: "Выберите профиль или папку", .de: "Profil oder Ordner auswählen"],
        "empty.create_in_tree": [.en: "Create folders and connection profiles in the left tree.", .ua: "Створюйте папки та профілі підключень у дереві зліва.", .ru: "Создавайте папки и профили подключений в дереве слева.", .de: "Erstellen Sie Ordner und Verbindungsprofile im linken Baum."],
        "empty.welcome.title": [.en: "Welcome to SQL Manager", .ua: "Ласкаво просимо до SQL Manager", .ru: "Добро пожаловать в SQL Manager", .de: "Willkommen bei SQL Manager"],
        "empty.welcome.description": [.en: "Create a folder or a profile to begin. You can disable this screen in Settings → General.", .ua: "Створіть папку або профіль, щоб почати. Цей екран можна вимкнути в Налаштуваннях → Загальні.", .ru: "Создайте папку или профиль, чтобы начать. Этот экран можно отключить в Настройках → Общие.", .de: "Erstellen Sie einen Ordner oder ein Profil, um zu beginnen. Diesen Bildschirm können Sie in Einstellungen → Allgemein deaktivieren."],
        "pane.profile_preview": [.en: "Profile Preview", .ua: "Попередній перегляд профілю", .ru: "Предпросмотр профиля", .de: "Profilvorschau"],
        "label.host": [.en: "Host", .ua: "Хост", .ru: "Хост", .de: "Host"],
        "label.status": [.en: "Status", .ua: "Статус", .ru: "Статус", .de: "Status"],
        "value.na": [.en: "n/a", .ua: "н/д", .ru: "н/д", .de: "k. A."],
        "empty.select_profile_preview": [.en: "Select profile to preview", .ua: "Оберіть профіль для перегляду", .ru: "Выберите профиль для просмотра", .de: "Profil zur Vorschau auswählen"],
        "empty.no_opened_connections": [.en: "No Opened Connections", .ua: "Немає відкритих підключень", .ru: "Нет открытых подключений", .de: "Keine geöffneten Verbindungen"],
        "empty.open_profile_card": [.en: "Open a profile and it will appear here as a card.", .ua: "Відкрийте профіль, і він з’явиться тут як картка.", .ru: "Откройте профиль, и он появится здесь как карточка.", .de: "Öffnen Sie ein Profil, und es erscheint hier als Karte."],
        "action.close": [.en: "Close", .ua: "Закрити", .ru: "Закрыть", .de: "Schließen"],
        "action.dismiss": [.en: "Dismiss", .ua: "Закрити", .ru: "Скрыть", .de: "Ausblenden"],
        "action.open_tab": [.en: "Open Tab", .ua: "Відкрити вкладку", .ru: "Открыть вкладку", .de: "Tab öffnen"],
        "action.connect": [.en: "Connect", .ua: "Підключити", .ru: "Подключить", .de: "Verbinden"],
        "action.disconnect": [.en: "Disconnect", .ua: "Відключити", .ru: "Отключить", .de: "Trennen"],
        "action.test_connection": [.en: "Test Connection", .ua: "Перевірити підключення", .ru: "Проверить подключение", .de: "Verbindung prüfen"],
        "action.test_tcp": [.en: "Test TCP", .ua: "Перевірити TCP", .ru: "Проверить TCP", .de: "TCP prüfen"],
        "action.refresh_schema": [.en: "Refresh Schema", .ua: "Оновити схему", .ru: "Обновить схему", .de: "Schema aktualisieren"],
        "action.preview_rows": [.en: "Preview Rows", .ua: "Перегляд рядків", .ru: "Просмотр строк", .de: "Zeilenvorschau"],
        "action.run_query": [.en: "Run Query", .ua: "Виконати запит", .ru: "Выполнить запрос", .de: "Abfrage ausführen"],
        "action.query_executed": [.en: "Query executed.", .ua: "Запит виконано.", .ru: "Запрос выполнен.", .de: "Abfrage ausgeführt."],
        "query.editor.title": [.en: "SQL Editor", .ua: "SQL редактор", .ru: "SQL редактор", .de: "SQL-Editor"],
        "query.results.title": [.en: "Query Results", .ua: "Результати запиту", .ru: "Результаты запроса", .de: "Abfrageergebnisse"],
        "query.results.empty": [.en: "Run a query or select a table to preview rows.", .ua: "Виконайте запит або оберіть таблицю для перегляду рядків.", .ru: "Выполните запрос или выберите таблицу для просмотра строк.", .de: "Führen Sie eine Abfrage aus oder wählen Sie eine Tabelle zur Vorschau aus."],
        "query.result.rows": [.en: "Rows", .ua: "Рядки", .ru: "Строки", .de: "Zeilen"],
        "query.result.affected": [.en: "Affected", .ua: "Змінено", .ru: "Изменено", .de: "Betroffen"],
        "query.result.duration": [.en: "Duration", .ua: "Тривалість", .ru: "Длительность", .de: "Dauer"],
        "name.new_folder": [.en: "New Folder", .ua: "Нова папка", .ru: "Новая папка", .de: "Neuer Ordner"],
        "name.new_connection": [.en: "New Connection", .ua: "Нове підключення", .ru: "Новое подключение", .de: "Neue Verbindung"],
        "settings.appearance": [.en: "Appearance", .ua: "Зовнішній вигляд", .ru: "Внешний вид", .de: "Darstellung"],
        "settings.connections": [.en: "Connections", .ua: "Підключення", .ru: "Подключения", .de: "Verbindungen"],
        "settings.language": [.en: "Language", .ua: "Мова", .ru: "Язык", .de: "Sprache"],
        "settings.language.section": [.en: "Localization", .ua: "Локалізація", .ru: "Локализация", .de: "Lokalisierung"],
        "settings.theme": [.en: "Theme", .ua: "Тема", .ru: "Тема", .de: "Thema"],
        "settings.theme.auto": [.en: "Auto", .ua: "Авто", .ru: "Авто", .de: "Auto"],
        "settings.theme.light": [.en: "Light", .ua: "Світла", .ru: "Светлая", .de: "Hell"],
        "settings.theme.dark": [.en: "Dark", .ua: "Темна", .ru: "Тёмная", .de: "Dunkel"],
        "settings.tab.general": [.en: "General", .ua: "Загальні", .ru: "Общие", .de: "Allgemein"],
        "settings.tab.appearance": [.en: "Appearance", .ua: "Вигляд", .ru: "Вид", .de: "Darstellung"],
        "settings.tab.behavior": [.en: "Behavior", .ua: "Поведінка", .ru: "Поведение", .de: "Verhalten"],
        "settings.tab.connections": [.en: "Connections", .ua: "Підключення", .ru: "Подключения", .de: "Verbindungen"],
        "settings.startup.section": [.en: "Startup", .ua: "Запуск", .ru: "Запуск", .de: "Start"],
        "settings.behavior.section": [.en: "Interaction", .ua: "Взаємодія", .ru: "Взаимодействие", .de: "Interaktion"],
        "settings.info.section": [.en: "Info", .ua: "Інфо", .ru: "Инфо", .de: "Info"],
        "settings.accent_color": [.en: "Accent Color", .ua: "Колір акценту", .ru: "Цвет акцента", .de: "Akzentfarbe"],
        "settings.accent.system": [.en: "System", .ua: "Системний", .ru: "Системный", .de: "System"],
        "settings.accent.blue": [.en: "Blue", .ua: "Синій", .ru: "Синий", .de: "Blau"],
        "settings.accent.green": [.en: "Green", .ua: "Зелений", .ru: "Зеленый", .de: "Grün"],
        "settings.accent.orange": [.en: "Orange", .ua: "Помаранчевий", .ru: "Оранжевый", .de: "Orange"],
        "settings.accent.red": [.en: "Red", .ua: "Червоний", .ru: "Красный", .de: "Rot"],
        "settings.accent.pink": [.en: "Pink", .ua: "Рожевий", .ru: "Розовый", .de: "Pink"],
        "settings.accent.indigo": [.en: "Indigo", .ua: "Індиго", .ru: "Индиго", .de: "Indigo"],
        "settings.show_colored_icons": [.en: "Show Colored Icons", .ua: "Показувати кольорові іконки", .ru: "Показывать цветные иконки", .de: "Farbige Symbole anzeigen"],
        "settings.compact_sidebar": [.en: "Compact Sidebar", .ua: "Компактний сайдбар", .ru: "Компактный сайдбар", .de: "Kompakte Seitenleiste"],
        "settings.show_welcome": [.en: "Show Welcome On Start", .ua: "Показувати вітання при запуску", .ru: "Показывать приветствие при запуске", .de: "Begrüßung beim Start anzeigen"],
        "settings.confirm_delete": [.en: "Confirm Deletion", .ua: "Підтверджувати видалення", .ru: "Подтверждать удаление", .de: "Löschen bestätigen"],
        "settings.auto_connect_profile": [.en: "Auto-connect Profiles", .ua: "Автопідключення профілів", .ru: "Автоподключение профилей", .de: "Profile automatisch verbinden"],
        "settings.run_query_shortcut": [.en: "Run Query: Cmd+Enter", .ua: "Виконати запит: Cmd+Enter", .ru: "Выполнить запрос: Cmd+Enter", .de: "Abfrage ausführen: Cmd+Enter"],
        "settings.use_ssl": [.en: "Use SSL by Default", .ua: "Використовувати SSL за замовчуванням", .ru: "Использовать SSL по умолчанию", .de: "SSL standardmäßig verwenden"],
        "settings.timeout_seconds": [.en: "Connection Timeout", .ua: "Таймаут підключення", .ru: "Таймаут подключения", .de: "Verbindungs-Timeout"],
        "settings.drivers_coming": [.en: "Connection drivers and secure storage will be added next.", .ua: "Драйвери підключень і безпечне сховище буде додано далі.", .ru: "Драйверы подключений и защищенное хранилище будут добавлены далее.", .de: "Verbindungstreiber und sicherer Speicher werden als Nächstes hinzugefügt."],
        "tab.connection_not_found": [.en: "Connection Not Found", .ua: "Підключення не знайдено", .ru: "Подключение не найдено", .de: "Verbindung nicht gefunden"],
        "field.database": [.en: "Database", .ua: "База даних", .ru: "База данных", .de: "Datenbank"],
        "field.method": [.en: "Method", .ua: "Метод", .ru: "Метод", .de: "Methode"],
        "field.ssl": [.en: "SSL", .ua: "SSL", .ru: "SSL", .de: "SSL"],
        "field.timeout": [.en: "Timeout", .ua: "Таймаут", .ru: "Таймаут", .de: "Timeout"],
        "form.general": [.en: "General", .ua: "Загальне", .ru: "Общее", .de: "Allgemein"],
        "form.connection": [.en: "Connection", .ua: "Підключення", .ru: "Подключение", .de: "Verbindung"],
        "field.name": [.en: "Name", .ua: "Назва", .ru: "Название", .de: "Name"],
        "field.icon": [.en: "Icon", .ua: "Іконка", .ru: "Иконка", .de: "Symbol"],
        "field.color": [.en: "Color", .ua: "Колір", .ru: "Цвет", .de: "Farbe"],
        "field.database_type": [.en: "Database Type", .ua: "Тип БД", .ru: "Тип БД", .de: "Datenbanktyp"],
        "field.host": [.en: "Host", .ua: "Хост", .ru: "Хост", .de: "Host"],
        "field.port": [.en: "Port", .ua: "Порт", .ru: "Порт", .de: "Port"],
        "field.username": [.en: "Username", .ua: "Користувач", .ru: "Пользователь", .de: "Benutzername"],
        "field.password": [.en: "Password", .ua: "Пароль", .ru: "Пароль", .de: "Passwort"],
        "action.open_in_tab": [.en: "Open in Tab", .ua: "Відкрити у вкладці", .ru: "Открыть во вкладке", .de: "Im Tab öffnen"],
        "status.connected": [.en: "Connected", .ua: "Підключено", .ru: "Подключено", .de: "Verbunden"],
        "status.disconnected": [.en: "Disconnected", .ua: "Відключено", .ru: "Отключено", .de: "Getrennt"],
        "status.connecting": [.en: "Connecting", .ua: "Підключення", .ru: "Подключение", .de: "Verbinde"],
        "status.testing_connection": [.en: "Testing connection...", .ua: "Перевірка підключення...", .ru: "Проверка подключения...", .de: "Verbindung wird geprüft..."],
        "status.connection_ok": [.en: "Connection is valid.", .ua: "Підключення валідне.", .ru: "Подключение валидно.", .de: "Verbindung ist gültig."],
        "status.testing_tcp": [.en: "Testing TCP endpoint...", .ua: "Перевірка TCP-ендпойнта...", .ru: "Проверка TCP-эндпоинта...", .de: "TCP-Endpunkt wird geprüft..."],
        "status.tcp_ok": [.en: "TCP is reachable:", .ua: "TCP доступний:", .ru: "TCP доступен:", .de: "TCP erreichbar:"],
        "status.loading_schema": [.en: "Loading schema...", .ua: "Завантаження схеми...", .ru: "Загрузка схемы...", .de: "Schema wird geladen..."],
        "schema.browser.title": [.en: "Schema Browser", .ua: "Огляд схеми", .ru: "Обзор схемы", .de: "Schema-Browser"],
        "schema.browser.empty": [.en: "No schema objects yet.", .ua: "Об’єкти схеми відсутні.", .ru: "Объекты схемы отсутствуют.", .de: "Keine Schemaobjekte vorhanden."],
        "preview.ready": [.en: "Preview: ready for query execution.", .ua: "Прев’ю: готово до виконання запитів.", .ru: "Превью: готово к выполнению запросов.", .de: "Vorschau: bereit zur Abfrageausführung."],
        "value.enabled": [.en: "Enabled", .ua: "Увімкнено", .ru: "Включено", .de: "Aktiviert"],
        "value.disabled": [.en: "Disabled", .ua: "Вимкнено", .ru: "Отключено", .de: "Deaktiviert"],
        "lang.system": [.en: "System", .ua: "Системна", .ru: "Системный", .de: "System"],
        "db.postgresql": [.en: "PostgreSQL", .ua: "PostgreSQL", .ru: "PostgreSQL", .de: "PostgreSQL"],
        "db.mysql": [.en: "MySQL", .ua: "MySQL", .ru: "MySQL", .de: "MySQL"],
        "db.sqlite": [.en: "SQLite", .ua: "SQLite", .ru: "SQLite", .de: "SQLite"],
        "db.mssql": [.en: "SQL Server", .ua: "SQL Server", .ru: "SQL Server", .de: "SQL Server"],
        "db.oracle": [.en: "Oracle", .ua: "Oracle", .ru: "Oracle", .de: "Oracle"],
        "method.host_port": [.en: "Host + Port", .ua: "Хост + Порт", .ru: "Хост + Порт", .de: "Host + Port"],
        "method.connection_string": [.en: "Connection String", .ua: "Рядок підключення", .ru: "Строка подключения", .de: "Verbindungszeichenfolge"],
        "method.ssh_tunnel": [.en: "SSH Tunnel", .ua: "SSH тунель", .ru: "SSH туннель", .de: "SSH-Tunnel"],
        "method.socket": [.en: "Local Socket", .ua: "Локальний сокет", .ru: "Локальный сокет", .de: "Lokaler Socket"],
        "color.default": [.en: "Default", .ua: "За замовчуванням", .ru: "По умолчанию", .de: "Standard"],
        "color.blue": [.en: "Blue", .ua: "Синій", .ru: "Синий", .de: "Blau"],
        "color.green": [.en: "Green", .ua: "Зелений", .ru: "Зеленый", .de: "Grün"],
        "color.orange": [.en: "Orange", .ua: "Помаранчевий", .ru: "Оранжевый", .de: "Orange"],
        "color.yellow": [.en: "Yellow", .ua: "Жовтий", .ru: "Желтый", .de: "Gelb"],
        "color.pink": [.en: "Pink", .ua: "Рожевий", .ru: "Розовый", .de: "Pink"],
        "color.red": [.en: "Red", .ua: "Червоний", .ru: "Красный", .de: "Rot"],
        "color.indigo": [.en: "Indigo", .ua: "Індиго", .ru: "Индиго", .de: "Indigo"],
        "color.purple": [.en: "Purple", .ua: "Фіолетовий", .ru: "Фиолетовый", .de: "Lila"],
        "color.gray": [.en: "Gray", .ua: "Сірий", .ru: "Серый", .de: "Grau"]
    ]
}
