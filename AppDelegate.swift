import Cocoa

// Note: This AppDelegate is not used when using SwiftUI App lifecycle
// The main entry point is in ZMKKeymapViewer.swift
// Keep this file for potential future use with AppKit integration

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the menu bar application interface here
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}