import SwiftUI

@main
struct HeartbeatAppApp: App {
    @StateObject private var viewModel = CheckinViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}
