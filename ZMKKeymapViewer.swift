import SwiftUI

@main
struct ZMKKeymapViewerApp: App {
    var body: some Scene {
        MenuBarExtra("ZMK Keymap Viewer") {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("Welcome to ZMK Keymap Viewer")
            .padding()
    }
}