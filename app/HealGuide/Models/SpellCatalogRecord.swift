import Foundation

// 동적 스킬 카탈로그의 영구 저장 단위.
//
// `SpellCatalogStore` 가 `~/Library/Application Support/HealGuide/spell_catalog.json`
// 에 {spellID: SpellCatalogRecord} 형태로 저장한다. 베이스라인은
// `SpecSpellCatalog` 의 하드코딩 spellID 리스트에서 오고, 이 저장소는 그 위에
// 올라가는 동적 확장(런타임 WCL masterData 추출 + Blizzard API 한국어 이름 fetch)
// 결과를 보관한다.
struct SpellCatalogRecord: Codable, Equatable, Hashable {
    let spellID: Int
    var nameKR: String
    var nameEN: String
    var iconURL: String?
    var firstSeenAt: Date
    var source: Source

    enum Source: String, Codable, Equatable {
        case baseline          // SpecSpellCatalog 하드코딩
        case wclMasterData     // WCL report.masterData.abilities 에서 발견
        case blizzardAPI       // Blizzard Game Data API 로 이름 확정
        case manual            // 사용자가 UI 에서 직접 추가
    }
}
