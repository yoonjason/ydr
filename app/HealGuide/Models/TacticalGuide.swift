import Foundation

// 사용자 큐레이션 기반 던전/보스 전술 가이드.
// 기존 Blizzard 설명 + 키워드 힌트 위에 '구체적 대응 방법' 레이어.
//
// 구조:
//   DungeonInfo.id → 보스(WCL 영문명) → [TacticalLine]
// TacticalLine.abilityName 은 Blizzard 가 반환하는 한국어 스킬명과 매칭.
enum TacticalPriority: String, Codable, Equatable {
    case critical   // ★ 필수
    case important  // ☆ 권장
    case note       // 일반 주의사항
}

struct TacticalLine: Codable, Equatable {
    let priority: TacticalPriority
    // 한국어 스킬명 (Blizzard ko_KR 과 매칭). 스킬 지정 없는 일반 주의는 빈 문자열 허용.
    let abilityName: String
    let action: String

    var priorityMarker: String {
        switch priority {
        case .critical:  return "★"
        case .important: return "☆"
        case .note:      return ""
        }
    }
}

// 보스 단위 공략. 던전별로 묶임.
// englishBossName 은 WCL dungeonPulls.name (영문) 과 매칭.
struct BossTacticalGuide: Equatable {
    let englishBossName: String
    let koreanBossName: String   // 사용자 표기 (참고용)
    let lines: [TacticalLine]
}
