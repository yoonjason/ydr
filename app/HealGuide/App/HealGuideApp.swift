import SwiftUI

@main
struct HealGuideApp: App {
    private static let catalogStore: SpellCatalogStore = {
        let store = SpellCatalogStore()
        store.seedIfNeeded()
        return store
    }()

    @StateObject private var viewModel = ReportViewModel(
        urlParser: URLParser(),
        keychain: FileCredentialStore(),
        apiClient: WarcraftLogsAPIClientImpl(),
        normalizer: TimelineNormalizer(),
        luaGenerator: LuaGenerator(),
        pasteboard: SystemPasteboard(),
        spellResolver: SpellResolver(store: catalogStore)
    )

    var body: some Scene {
        WindowGroup { ContentView(viewModel: viewModel) }
    }
}
