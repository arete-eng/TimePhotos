//
//  TimePhotosApp.swift
//  TimePhotos
//
//  Created by Rebecca P on 10/31/25.
//

import SwiftUI

@main
struct TimePhotosApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .windowSize) {
                Button("Zoom In") {
                    NotificationCenter.default.post(name: NSNotification.Name("ZoomIn"), object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("Zoom Out") {
                    NotificationCenter.default.post(name: NSNotification.Name("ZoomOut"), object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button("Reset Zoom") {
                    NotificationCenter.default.post(name: NSNotification.Name("ResetZoom"), object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
