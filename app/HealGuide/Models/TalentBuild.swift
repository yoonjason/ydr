import Foundation

// WCL ReportFight.talentImportCode 결과 1건 (단일 랭커의 export 문자열).
struct TalentImportSample: Identifiable, Equatable {
    let reportCode:    String
    let fightID:       Int
    let characterName: String
    let importCode:    String   // WoW 인게임 붙여넣기 가능 export 문자열

    var id: String { "\(reportCode)-\(fightID)" }

    // WarcraftLogs 리포트 URL (특정 fight 로 바로 이동).
    var warcraftLogsURL: URL? {
        URL(string: "https://www.warcraftlogs.com/reports/\(reportCode)#fight=\(fightID)")
    }
}

// 동일 importCode 로 그룹핑된 빌드 집계 결과.
struct TalentBuildGroup: Identifiable, Equatable {
    let importCode:    String
    let samples:       [TalentImportSample]   // 이 빌드를 사용한 랭커들의 원본 샘플
    let totalSamples:  Int                     // 전체 표본 크기 (분모)

    var id: String { importCode }
    var usageCount: Int { samples.count }
    var characterNames: [String] { samples.map(\.characterName) }
    var usageRatio: Double {
        guard totalSamples > 0 else { return 0 }
        return Double(usageCount) / Double(totalSamples)
    }
}

// 전체 수집 결과 (View 에 직접 바인딩).
struct TalentBuildCollectionResult: Equatable {
    let spec:            HealerSpec
    let dungeonName:     String
    let difficulty:      RankerDifficulty
    let collectedAt:     Date
    let totalSamples:    Int   // 실제 import 문자열 획득 성공한 파스 수
    let requestedRankers: Int  // 사용자 요청 TopN
    let groups:          [TalentBuildGroup]   // 빈도 내림차순
}
