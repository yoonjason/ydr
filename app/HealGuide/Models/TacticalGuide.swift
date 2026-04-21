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

    // ASCII 마커 — WoW 클라이언트 기본 폰트가 ★/☆ (U+2605/2606) 글리프 미포함일 수 있어
    // tofu 렌더 위험. 색상 구분은 별도로 적용되므로 마커는 간결한 문자로 유지.
    var priorityMarker: String {
        switch priority {
        case .critical:  return "[!]"
        case .important: return "[~]"
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

// Lua 출력용 인카운터 전술 요약. LuaGenerator 에 전달해 tactics 블록 생성.
struct EncounterTacticsSummary: Equatable {
    // abilityName 이 빈 라인 — 보스 전체 주의사항.
    let shared: [TacticalLine]
    // 보스 어빌리티 spellID → 해당 스킬 전술 라인.
    let perAbility: [Int: [TacticalLine]]
}
