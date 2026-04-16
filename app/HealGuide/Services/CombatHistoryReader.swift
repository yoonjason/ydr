import Foundation
import os

struct CombatHistoryReader {
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "CombatHistoryReader")

    func read(wtfCharacterPath: String) -> [CombatRecord] {
        let filePath = (wtfCharacterPath as NSString)
            .appendingPathComponent("SavedVariables/HealGuideCharDB.lua")
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            logger.info("SavedVariables 파일 없음: \(filePath)")
            return []
        }

        guard content.contains("combatHistory") else { return [] }

        // SavedVariables Lua 파싱: loadstring 대용으로 간이 추출
        // combatHistory 테이블 내 각 record 를 정규식으로 추출
        // 완전한 Lua 파서는 오버킬 — 구조화된 SavedVariables 패턴만 처리
        return parseCombatHistory(content)
    }

    private func parseCombatHistory(_ content: String) -> [CombatRecord] {
        var records: [CombatRecord] = []

        // encounterID, timestamp, duration, stats 를 간이 추출
        let recordPattern = #"encounterID\s*=\s*(\d+)"#
        let timestampPattern = #"(?<!\w)timestamp\s*=\s*(\d+)"#
        let durationPattern = #"duration\s*=\s*([\d.]+)"#
        let firedPattern = #"fired\s*=\s*(\d+)"#
        let conditionSkippedPattern = #"conditionSkipped\s*=\s*(\d+)"#
        let cooldownSkippedPattern = #"cooldownSkipped\s*=\s*(\d+)"#
        let usedPattern = #"used\s*=\s*(\d+)"#

        // combatHistory 블록 내에서 record 블록 단위 분리
        guard let historyRange = content.range(of: "combatHistory") else { return [] }
        let historyContent = String(content[historyRange.lowerBound...])

        // 간이 분리: 각 { encounterID = ... } 블록
        let blocks = historyContent.components(separatedBy: "encounterID")
        for block in blocks.dropFirst() {
            let fullBlock = "encounterID" + block

            guard let encounterID = extractInt(fullBlock, pattern: recordPattern),
                  let timestamp = extractInt(fullBlock, pattern: timestampPattern),
                  let duration = extractDouble(fullBlock, pattern: durationPattern) else {
                continue
            }

            let stats = CombatStats(
                fired: extractInt(fullBlock, pattern: firedPattern) ?? 0,
                conditionSkipped: extractInt(fullBlock, pattern: conditionSkippedPattern) ?? 0,
                cooldownSkipped: extractInt(fullBlock, pattern: cooldownSkippedPattern) ?? 0,
                used: extractInt(fullBlock, pattern: usedPattern) ?? 0
            )

            records.append(CombatRecord(
                encounterID: encounterID,
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                duration: duration,
                stats: stats,
                events: []
            ))
        }

        return records
    }

    private func extractInt(_ text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }

    private func extractDouble(_ text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }
}
