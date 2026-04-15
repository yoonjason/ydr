import SwiftUI

@main
struct HealGuideApp: App {
    @StateObject private var viewModel = ReportViewModel(
        urlParser: URLParser(),
        keychain: FileCredentialStore(),
        apiClient: WarcraftLogsAPIClientImpl(),
        normalizer: TimelineNormalizer(),
        luaGenerator: LuaGenerator(),
        pasteboard: SystemPasteboard()
    )

    var body: some Scene {
        WindowGroup { ContentView(viewModel: viewModel) }
    }
}
