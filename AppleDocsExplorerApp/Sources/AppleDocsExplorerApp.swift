import DocsCore
import SwiftUI

@main
struct AppleDocsExplorerApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .task {
                    await appModel.bootstrap()
                }
        }
        .defaultSize(width: 1320, height: 860)
    }
}
