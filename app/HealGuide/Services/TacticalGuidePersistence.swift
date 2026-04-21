import Foundation
import os

// 사용자 편집 전술 가이드 JSON 영속화.
// 위치: Application Support/HealGuide/tactical_guide_custom.json
//
// 하드코딩 default (TacticalGuideCatalog) + 사용자 override 병합으로 최종 결과 사용.
// 병합 규칙: 동일 (dungeonID, englishBossName) 키가 있으면 사용자 편집이 default 교체.

// MARK: - JSON 포맷

struct TacticalGuideCustomFile: Codable, Equatable {
    var version: Int = 1
    var createdAt: String
    var author: String?
    var customizations: [DungeonCustomization]

    init(
        version: Int = 1,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        author: String? = nil,
        customizations: [DungeonCustomization] = []
    ) {
        self.version = version
        self.createdAt = createdAt
        self.author = author
        self.customizations = customizations
    }
}

struct DungeonCustomization: Codable, Equatable {
    var dungeonID: Int
    var bosses: [BossCustomization]
}

struct BossCustomization: Codable, Equatable {
    var englishBossName: String
    var koreanBossName: String
    var lines: [TacticalLine]
}

// MARK: - Service

final class TacticalGuidePersistence {
    static let shared = TacticalGuidePersistence()

    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "TacticalGuide")
    private let fileManager = FileManager.default

    /// 기본 저장 파일 경로.
    var defaultURL: URL {
        let dir = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealGuide")
        return dir.appendingPathComponent("tactical_guide_custom.json")
    }

    /// 저장된 커스텀 파일 로드. 없으면 nil (+ 오류 시 nil + 로그).
    func load(from url: URL? = nil) -> TacticalGuideCustomFile? {
        let target = url ?? defaultURL
        guard fileManager.fileExists(atPath: target.path) else { return nil }
        do {
            let data = try Data(contentsOf: target)
            return try JSONDecoder().decode(TacticalGuideCustomFile.self, from: data)
        } catch {
            logger.warning("TacticalGuideCustom 로드 실패: \(error)")
            return nil
        }
    }

    /// 파일에 저장 (atomic). 디렉토리 없으면 생성.
    @discardableResult
    func save(_ file: TacticalGuideCustomFile, to url: URL? = nil) -> Bool {
        let target = url ?? defaultURL
        do {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: target, options: .atomic)
            return true
        } catch {
            logger.error("TacticalGuideCustom 저장 실패: \(error)")
            return false
        }
    }
}
