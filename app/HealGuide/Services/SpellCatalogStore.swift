import Foundation
import os

// `SpellCatalogStoring` 의 파일 기반 구현.
//
// 저장 경로: `~/Library/Application Support/HealGuide/spell_catalog.json`
// 포맷: JSON dictionary `{ "<spellID>": { spellID, nameKR, nameEN, firstSeenAt, source } }`
// 동시성: 단일 프로세스(Mac 앱) 전제. 직렬 큐로 파일 I/O 를 serialize.
final class SpellCatalogStore: SpellCatalogStoring {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.yeongseok.healguide.SpellCatalogStore")
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "SpellCatalogStore")

    private var cache: [Int: SpellCatalogRecord] = [:]
    private var cacheLoaded = false

    init(fileName: String = "spell_catalog.json") {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("HealGuide", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        self.fileURL = dir.appendingPathComponent(fileName)
    }

    func loadAll() -> [Int: SpellCatalogRecord] {
        queue.sync {
            ensureLoaded()
            return cache
        }
    }

    func record(for spellID: Int) -> SpellCatalogRecord? {
        queue.sync {
            ensureLoaded()
            return cache[spellID]
        }
    }

    func upsert(_ record: SpellCatalogRecord) throws {
        try queue.sync {
            ensureLoaded()
            mergeIntoCache(record)
            try writeUnlocked()
        }
    }

    func upsertMany(_ records: [SpellCatalogRecord]) throws {
        try queue.sync {
            ensureLoaded()
            for record in records { mergeIntoCache(record) }
            try writeUnlocked()
        }
    }

    func delete(spellID: Int) throws {
        try queue.sync {
            ensureLoaded()
            cache.removeValue(forKey: spellID)
            try writeUnlocked()
        }
    }

    func missingSpellIDs(from candidates: [Int]) -> [Int] {
        queue.sync {
            ensureLoaded()
            return candidates.filter { cache[$0] == nil }
        }
    }

    // MARK: - Private

    private func ensureLoaded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true

        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 저장 포맷은 문자열 키(JSON 제약). Int 로 복원.
        if let stringKeyed = try? decoder.decode([String: SpellCatalogRecord].self, from: data) {
            var result: [Int: SpellCatalogRecord] = [:]
            for (key, value) in stringKeyed {
                if let id = Int(key) { result[id] = value }
            }
            cache = result
            return
        }

        logger.warning("spell_catalog.json 디코딩 실패 — 빈 카탈로그로 시작")
    }

    private func mergeIntoCache(_ incoming: SpellCatalogRecord) {
        if let existing = cache[incoming.spellID] {
            var merged = incoming
            merged.firstSeenAt = existing.firstSeenAt  // 최초 발견 시점 유지
            cache[incoming.spellID] = merged
        } else {
            cache[incoming.spellID] = incoming
        }
    }

    private func writeUnlocked() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var stringKeyed: [String: SpellCatalogRecord] = [:]
        for (key, value) in cache {
            stringKeyed[String(key)] = value
        }

        let data = try encoder.encode(stringKeyed)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
