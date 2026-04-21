import Foundation

// MARK: - Protocol

protocol RankerDataMerger {
    /// 수집된 파스들의 보스→힐 쌍을 Welford 통계 + 다수결 필터로 병합.
    /// encounterNames: 수집 시점에 WCL dungeonPulls.name 에서 모은 [encID: 한국어 이름].
    /// per-pull encID 는 worldData.encounter(id:).name 네임스페이스에 없어 런타임 Blizzard/WCL
    /// 조회 실패 → 이 시점에 미리 캡처해둔 이름만 신뢰 가능.
    func merge(
        parses:         [(parse: RankerParse, bossPairs: [BossHealPair])],
        meta:           HGPTRankerDataMeta,
        encounterNames: [Int: String]
    ) -> HGPTRankerData

    /// 병합 결과에서 미리보기용 요약 생성
    func buildPreview(
        parsesCollected: Int,
        parsesFiltered:  Int,
        data:            HGPTRankerData
    ) -> RankerPreviewResult
}

// MARK: - Implementation

struct RankerDataMergerImpl: RankerDataMerger {

    // 표준편차 경고 임계값 (초)
    static let highStddevThreshold: Double = 2.0

    func merge(
        parses:         [(parse: RankerParse, bossPairs: [BossHealPair])],
        meta:           HGPTRankerDataMeta,
        encounterNames: [Int: String] = [:]
    ) -> HGPTRankerData {
        guard !parses.isEmpty else {
            return HGPTRankerData(meta: meta, encounterData: [:], encounterNames: encounterNames)
        }

        let totalParses = parses.count

        // (bossHealKey) → Welford 누산 + 등장 파스 수
        var accumulators: [BossHealKey: WelfordAccumulator] = [:]
        var parseCountPerKey: [BossHealKey: Int] = [:]

        for parseTuple in parses {
            for pair in parseTuple.bossPairs {
                let key = BossHealKey(
                    encounterID: pair.encounterID,
                    bossSpellID: pair.bossSpellID,
                    healSpellID: pair.healSpellID
                )
                accumulators[key, default: WelfordAccumulator()].update(pair.delaySeconds)
                parseCountPerKey[key, default: 0] += 1
            }
        }

        // 다수결 임계값: ⌈N/2⌉
        let quorumThreshold = Int(ceil(Double(totalParses) / 2.0))

        var encounterData: [Int: [Int: [RankerResponseEntry]]] = [:]

        for (key, accumulator) in accumulators {
            guard let parseCount = parseCountPerKey[key],
                  parseCount >= quorumThreshold else { continue }

            let entry = RankerResponseEntry(
                spellID: key.healSpellID,
                delay:   accumulator.mean,
                stddev:  accumulator.stddev,
                count:   accumulator.count,
                quorum:  "\(parseCount)/\(totalParses)"
            )

            encounterData[key.encounterID, default: [:]][key.bossSpellID, default: []].append(entry)
        }

        // delay 오름차순 정렬
        for encID in encounterData.keys {
            for bossID in (encounterData[encID] ?? [:]).keys {
                encounterData[encID]?[bossID]?.sort { $0.delay < $1.delay }
            }
        }

        return HGPTRankerData(meta: meta, encounterData: encounterData, encounterNames: encounterNames)
    }

    // MARK: - 미리보기 결과 생성

    func buildPreview(
        parsesCollected: Int,
        parsesFiltered:  Int,
        data:            HGPTRankerData
    ) -> RankerPreviewResult {
        var bossEntries: [RankerPreviewResult.BossEntry] = []
        var warnings: [String] = []

        for (encID, bossMap) in data.encounterData.sorted(by: { $0.key < $1.key }) {
            let encName = data.encounterNames[encID]
            for (bossID, entries) in bossMap.sorted(by: { $0.key < $1.key }) {
                bossEntries.append(.init(
                    encounterID:   encID,
                    bossSpellID:   bossID,
                    mappingCount:  entries.count,
                    encounterName: encName,
                    bossSpellName: nil
                ))
                for entry in entries where entry.stddev >= Self.highStddevThreshold {
                    warnings.append("Enc\(encID)-Boss\(bossID)-Spell\(entry.spellID): stddev \(String(format: "%.1f", entry.stddev))s")
                }
            }
        }

        return RankerPreviewResult(
            parsesCollected: parsesCollected,
            parsesFiltered:  parsesFiltered,
            bossEntries:     bossEntries,
            highVarianceWarnings: warnings
        )
    }
}

// MARK: - Internal Key

private struct BossHealKey: Hashable {
    let encounterID: Int
    let bossSpellID: Int
    let healSpellID: Int
}
