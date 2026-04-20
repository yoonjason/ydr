import Foundation

// WCL ReportFight.talentImportCode 결과 1건 (단일 랭커의 export 문자열).
struct TalentImportSample: Equatable {
    let reportCode:    String
    let fightID:       Int
    let characterName: String
    let importCode:    String   // WoW 인게임 붙여넣기 가능 export 문자열
}

// 동일 importCode 로 그룹핑된 빌드 집계 결과.
struct TalentBuildGroup: Identifiable, Equatable {
    let importCode:    String
    let usageCount:    Int
    let totalSamples:  Int
    // 이 빌드를 사용한 랭커 이름 목록 (예: "Mintchu, 에이네, Cristiana")
    let characterNames: [String]

    var id: String { importCode }
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
