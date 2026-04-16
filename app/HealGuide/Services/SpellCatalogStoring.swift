import Foundation

// 동적 스킬 카탈로그의 영구 저장 계층.
//
// 베이스라인(`SpecSpellCatalog`)과 별도로 런타임에 발견되는 스킬을 누적한다.
// WCL masterData 에서 발견된 spellID 를 upsert 하고, Blizzard API 로 fetch 한
// 한국어 이름을 해당 레코드에 머지한다.
protocol SpellCatalogStoring {
    // 전체 레코드 로드 (spellID → record).
    func loadAll() -> [Int: SpellCatalogRecord]

    // 단일 조회.
    func record(for spellID: Int) -> SpellCatalogRecord?

    // 신규/갱신. 동일 spellID 가 이미 있으면 nameKR/nameEN/source 를 덮어씀.
    // firstSeenAt 은 기존 값 유지.
    func upsert(_ record: SpellCatalogRecord) throws

    // 배치 upsert. 신규 import 흐름에서 다수 스킬을 한 번에 저장할 때 사용.
    func upsertMany(_ records: [SpellCatalogRecord]) throws

    // 삭제 (주로 테스트용).
    func delete(spellID: Int) throws

    // 카탈로그에 존재하지 않는 spellID 만 필터 — 신규 스킬 감지 시 사용.
    func missingSpellIDs(from candidates: [Int]) -> [Int]
}
