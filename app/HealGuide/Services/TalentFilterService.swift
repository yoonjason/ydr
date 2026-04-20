import Foundation

// MARK: - Protocol

protocol TalentFilterService {
    /// 방식 A (Jaccard) + 방식 C (프리셋) AND 조건으로 파스 필터링
    func filter(_ parses: [RankerParse], using config: TalentFilterConfig) -> [RankerParse]

    /// Blizzard 탤런트 익스포트 스트링 파싱 → 선택된 노드 ID 집합
    /// 파싱 실패 시 nil 반환
    func parseTalentString(_ string: String) -> Set<Int>?
}

// MARK: - Implementation

struct TalentFilterServiceImpl: TalentFilterService {
    func filter(_ parses: [RankerParse], using config: TalentFilterConfig) -> [RankerParse] {
        parses.filter { parse in
            passesPresetFilter(parse, preset: config.preset) &&
            passesStringFilter(parse, talentString: config.talentString, threshold: config.jaccardThreshold)
        }
    }

    func parseTalentString(_ string: String) -> Set<Int>? {
        guard !string.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        // Blizzard 탤런트 익스포트 스트링 (TWW/Dragonflight 버전 0 포맷)
        // 포맷: Base64 인코딩된 비트 스트림
        //   [8 bits] version = 0
        //   [16 bits] specID (LE)
        //   [각 선택 탤런트에 대해]: 1 bit active + 6 bits rank + 19 bits nodeID
        //
        // NOTE: 실제 트리별 노드 순서가 필요하므로 순수 오프셋 파싱으로는 한계가 있음.
        // 19-bit 정수 중 TWW 노드 범위(80000–200000)에 해당하는 값을 휴리스틱으로 추출.
        // 보다 정확한 구현은 Blizzard API /data/wow/talent-tree/{treeID}/spec/{specID} 스키마 필요.

        let padded = string + String(repeating: "=", count: (4 - string.count % 4) % 4)
        guard let data = Data(base64Encoded: padded, options: .ignoreUnknownCharacters),
              data.count >= 3 else { return nil }

        let versionByte = Int(data[0])
        guard versionByte == 0 || versionByte == 1 else { return nil }

        // 비트 스트림 리더 (MSB first)
        var bitOffset = 24  // 3 bytes 헤더 건너뜀
        var extractedIDs = Set<Int>()

        func readBits(_ count: Int) -> Int? {
            var result = 0
            for i in 0..<count {
                let byteIndex = (bitOffset + i) / 8
                let bitIndex  = 7 - (bitOffset + i) % 8
                guard byteIndex < data.count else { return nil }
                let bit = (Int(data[byteIndex]) >> bitIndex) & 1
                result = (result << 1) | bit
            }
            bitOffset += count
            return result
        }

        // 각 엔트리: 1(active) + 6(rank) + 19(nodeID) = 26 bits
        while bitOffset + 26 <= data.count * 8 {
            guard let active = readBits(1) else { break }
            guard readBits(6) != nil else { break }   // rank (consume)
            guard let nodeID = readBits(19) else { break }
            if active == 1 && nodeID >= 80_000 && nodeID <= 200_000 {
                extractedIDs.insert(nodeID)
            }
        }

        return extractedIDs.isEmpty ? nil : extractedIDs
    }

    // MARK: - Private

    private func passesPresetFilter(_ parse: RankerParse, preset: TalentPreset?) -> Bool {
        guard let preset else { return true }
        guard !preset.coreTalentNodeIDs.isEmpty || !preset.excludeTalentNodeIDs.isEmpty else {
            return true  // TODO 아직 노드 ID 미설정 → 프리셋 필터 통과
        }
        let hasAllCore    = preset.coreTalentNodeIDs.isSubset(of: parse.talentNodeIDs)
        let hasNoExcluded = preset.excludeTalentNodeIDs.isDisjoint(with: parse.talentNodeIDs)
        return hasAllCore && hasNoExcluded
    }

    private func passesStringFilter(
        _ parse: RankerParse,
        talentString: String?,
        threshold: Double
    ) -> Bool {
        guard let string = talentString, !string.trimmingCharacters(in: .whitespaces).isEmpty else {
            return true
        }
        guard let userNodeIDs = parseTalentString(string), !userNodeIDs.isEmpty else {
            return false  // 파싱 실패 → 통과 불가 (안전 실패)
        }
        return jaccardSimilarity(userNodeIDs, parse.talentNodeIDs) >= threshold
    }

    // MARK: - Jaccard Similarity

    func jaccardSimilarity(_ a: Set<Int>, _ b: Set<Int>) -> Double {
        let intersectionCount = a.intersection(b).count
        let unionCount        = a.union(b).count
        guard unionCount > 0 else { return 1.0 }
        return Double(intersectionCount) / Double(unionCount)
    }
}
