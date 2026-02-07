import SwiftUI

@main
struct MathsChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var engine = ChatEngine(config: ConnectionConfig())
    @State private var showConnectionSheet = true

    var body: some Scene {
        WindowGroup {
            if showConnectionSheet {
                ConnectionSheet(isPresented: $showConnectionSheet) { config, isInitiator in
                    engine.connect(with: config, isInitiator: isInitiator)
                    showConnectionSheet = false
                }
                .frame(width: 500, height: 400)
            } else {
                ChatView(engine: engine)
                    .frame(minWidth: 600, minHeight: 500)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Disconnect") {
                                engine.disconnect()
                                showConnectionSheet = true
                            }
                        }
                    }
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection") {
                    engine.disconnect()
                    showConnectionSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
