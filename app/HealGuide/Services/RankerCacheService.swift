import Foundation
import os

/// 수집된 RankerData 엔트리를 JSON 캐시 파일로 관리.
/// (spec, dungeonID, difficulty) 가 같으면 교체, 없으면 append.
final class RankerCacheService {
    private let cacheURL: URL
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "RankerCache")

    init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL ?? RankerCacheService.defaultCacheURL
    }

    /// 새 entry 를 캐시에 병합하고 전체 entries 를 반환.
    func merge(_ newEntry: HGPTRankerData) -> [HGPTRankerData] {
        var entries = load()
        let newKey = entryKey(for: newEntry.meta)

        if let index = entries.firstIndex(where: { entryKey(for: $0.meta) == newKey }) {
            entries[index] = newEntry
            logger.info("RankerCache: 기존 항목 교체 (spec=\(newKey.spec), dungeonID=\(newKey.dungeonID), difficulty=\(newKey.difficulty))")
        } else {
            entries.append(newEntry)
            logger.info("RankerCache: 새 항목 추가 (spec=\(newKey.spec), dungeonID=\(newKey.dungeonID), difficulty=\(newKey.difficulty)), 총 \(entries.count)개")
        }

        save(entries)
        return entries
    }

    // MARK: - Private

    private struct EntryKey: Hashable {
        let spec: String
        let dungeonID: Int
        let difficulty: String
    }

    private func entryKey(for meta: HGPTRankerDataMeta) -> EntryKey {
        EntryKey(spec: meta.spec, dungeonID: meta.dungeonID, difficulty: meta.difficulty)
    }

    private func load() -> [HGPTRankerData] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        do {
            return try JSONDecoder().decode([HGPTRankerData].self, from: data)
        } catch {
            logger.warning("RankerCache 로드 실패 — 빈 캐시로 초기화: \(error)")
            return []
        }
    }

    private func save(_ entries: [HGPTRankerData]) {
        do {
            let directory = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            logger.error("RankerCache 저장 실패: \(error)")
        }
    }

    static var defaultCacheURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealGuide/rankerCache.json")
    }
}
