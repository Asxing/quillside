//
//  QuillsideApp.swift
//  Quillside
//
//  Created on 2026-01-28.
//

import SwiftUI

@main
struct QuillsideApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // A settings-only scene keeps this utility from opening a document
        // window on launch. AppKit owns the status item and explicit windows.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("设置…") {
                        SettingsWindowController.shared.show(appState: appDelegate.appState)
                    }.keyboardShortcut(",")
                }
            }
    }
}
