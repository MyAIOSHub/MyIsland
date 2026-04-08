//
//  MyIslandApp.swift
//  MyIsland
//
//  Dynamic Island for monitoring Claude Code instances
//

import SwiftUI

@main
struct MyIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use a completely custom window, so no default scene needed
        Settings {
            EmptyView()
        }
    }
}
