import SwiftUI

@main
struct HealGuideApp: App {
    private static let catalogStore: SpellCatalogStore = {
        let store = SpellCatalogStore()
        store.seedIfNeeded()
        return store
    }()

    @StateObject private var reportViewModel = ReportViewModel(
        urlParser: URLParser(),
        keychain: FileCredentialStore(),
        apiClient: WarcraftLogsAPIClientImpl(),
        normalizer: TimelineNormalizer(),
        luaGenerator: LuaGenerator(),
        pasteboard: SystemPasteboard(),
        spellResolver: SpellResolver(store: catalogStore)
    )

    @StateObject private var rankerViewModel = RankerCollectionViewModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(viewModel: reportViewModel)
                    .tabItem { Label("로그 분석", systemImage: "doc.text.magnifyingglass") }

                RankerCollectionTab(viewModel: rankerViewModel)
                    .tabItem { Label("랭커 수집", systemImage: "person.2.badge.gearshape") }
            }
        }
    }
}
