//
//  sqlmanagerApp.swift
//  sqlmanager
//
//  Created by Oflance on 15.03.2026.
//

import SwiftUI

@main
struct sqlmanagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            ProfileImportCommands()
        }
    }
}
