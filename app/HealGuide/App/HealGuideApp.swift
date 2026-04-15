import SwiftUI

@main
struct HealGuideApp: App {
    @StateObject private var viewModel = ReportViewModel(
        urlParser: URLParser(),
        keychain: KeychainWrapper(),
        apiClient: WarcraftLogsAPIClientImpl()
    )

    var body: some Scene {
        WindowGroup { ContentView(viewModel: viewModel) }
    }
}
