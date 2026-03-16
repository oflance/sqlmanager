//
//  ProfileImportCommands.swift
//  sqlmanager
//

import Foundation
import SwiftUI

extension Notification.Name {
    static let importProfilesRequested = Notification.Name("importProfilesRequested")
}

struct ProfileImportCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Menu("Import Profiles") {
                ForEach(ProfileImportSource.allCases) { source in
                    Button(source.menuTitle) {
                        NotificationCenter.default.post(name: .importProfilesRequested, object: source.rawValue)
                    }
                }
            }
        }
    }
}
