# Changelog

## [1.2.0] - 2026-03-18

### Added
- Native MySQL adapter support with schema introspection (tables, views, indexes, constraints).
- Password field in profile editor with Keychain persistence integration.
- `Test Connection` action in profile settings.
- `Test TCP` action in connection tab for fast endpoint diagnostics.
- Schema Browser in the connection workspace with refresh and table row preview actions.
- Query results grid with column headers and row rendering for executed SQL.
- SQL suggestion chips (keywords + discovered schema objects).
- Dedicated views:
  - `ConnectionWorkspaceView` for connection tab UI.
  - `ProfileNodeEditorContainerView` for profile editor orchestration.

### Changed
- Connection flow now uses stored Keychain credentials instead of always connecting with no credential.
- Connection tabs now load schema after successful connect and clear schema/result state on disconnect/close.
- Connection workspace redesigned to a split layout: left schema pane, right data/editor pane.
- `ContentView` significantly simplified by extracting large tab/editor logic into dedicated views.

### Fixed
- App Sandbox networking setup for outgoing connections in Debug/Release target settings.
- Improved adapter error mapping for low-level NIO socket errors.
- Added explicit network diagnostics for common errno cases (`1`, `54`, `60`, `61`).
- Fixed TCP test endpoint mapping for SSH tunnel profiles to use target host/port.

---

## [1.1.0] - 2026-03-18

### Added
- About Window metadata.
- Sidebar search/filter.
- Search placeholder localization.
- Clear search button.

### Changed
- Sidebar search now shows matching items in expanded view.
- Settings moved to a gear icon near the search field.
- Removed old bottom Settings button.
- Cleaned project rename leftovers.

### Fixed
- MainActor isolation issues in importer helpers.
- Build stability after recent UI and project updates.

---

## [1.0.0] - 2026-03-15

### Added
- Initial release of SQL Manager core app structure.
