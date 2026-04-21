import Foundation

// Blizzard Journal Encounter ability description (한국어) 에서 키워드를 추출해
// 힐러 범용 대응 가이드를 생성.
//
// 원칙: false positive 보다 false negative 우선. 애매한 경우 힌트를 안 주는 게 나음.
// 특정 기믹 대응 (예: 보주 분산, 외곽 유도) 은 범위 밖 — 이건 수동 큐레이션/LLM 영역.
enum HealerHintGenerator {

    /// Blizzard 설명 문자열 → 힐러 범용 가이드 배열 (없으면 빈 배열).
    /// 여러 힌트가 모두 해당될 수 있음 (예: "광역 도트" → 광역 힐 + HOT).
    static func generate(from description: String) -> [String] {
        guard !description.isEmpty else { return [] }

        // NSString 소문자 변환 대신 한국어 원문 그대로 substring 매칭.
        // 영문 혼용 케이스 대비 lowercased 버전도 함께 만들어둠.
        let raw = description
        let lower = description.lowercased()
        var hints: [String] = []

        // 1. 광역 / 전체 피해
        if raw.contains("광역") || raw.contains("모든 적") || raw.contains("모든 대상")
            || raw.contains("주위") || raw.contains("주변의") || raw.contains("파티원") {
            hints.append("[광역] 파티 광역 힐 준비")
        }

        // 2. 지속 피해 (DOT)
        if raw.contains("도트") || raw.contains("지속 피해") || raw.contains("초간")
            || raw.contains("점화") || raw.contains("틱") || lower.contains("dot") {
            hints.append("[HOT] 유지 / 꾸준한 힐")
        }

        // 3. 정화 필요 디버프
        if raw.contains("해제") || raw.contains("정화") || raw.contains("마법 디버프")
            || raw.contains("저주") || raw.contains("독") || raw.contains("질병") {
            hints.append("[정화] 준비")
        }

        // 4. 이동 / 넉백
        if raw.contains("넉백") || raw.contains("밀어") || raw.contains("날려") || raw.contains("밀쳐")
            || raw.contains("끌어당") || raw.contains("빨아들") {
            hints.append("[이동] 위치 복귀 후 힐")
        }

        // 5. 공포 / 제어 / CC
        if raw.contains("공포") || raw.contains("기절") || raw.contains("침묵") || raw.contains("조종") {
            hints.append("[CC] 마공방 / 팔라 자유 대응")
        }

        // 6. 강력한 단일 타겟 대미지 (탱크 크리 위험)
        if (raw.contains("대량의") || raw.contains("강력한") || raw.contains("치명적") || raw.contains("처형"))
            && (raw.contains("대미지") || raw.contains("피해")) {
            hints.append("[탱힐] 탱커 보호 / 방어쿨")
        }

        // 7. 분산 / 표식 / 지정
        if raw.contains("표식") || raw.contains("지정된 대상") || raw.contains("임의의")
            || raw.contains("대상을 선택") {
            hints.append("[표적] 주위 상황 확인")
        }

        // 8. 회피 가능 / 장판
        // NIT-3: "지역" 단독 매칭 제거 — 위치 묘사 ("이 지역에서 활동") 과 구분 어려움.
        // "지역 피해" / "특정 지역" 같은 명시적 기믹 문구만 허용.
        if raw.contains("회피") || raw.contains("피해야") || raw.contains("장판")
            || raw.contains("바닥") || raw.contains("지역 피해") || raw.contains("특정 지역") {
            hints.append("[장판] 회피 후 힐")
        }

        // 9. 중첩 / 스택
        if raw.contains("중첩") || raw.contains("누적") || raw.contains("스택") || lower.contains("stack") {
            hints.append("[중첩] 관리 주의")
        }

        // 10. 소환물 / 추가 개체
        if raw.contains("소환") || raw.contains("추가 개체") || raw.contains("제단") {
            hints.append("[소환물] 추가 몹 힐 관리")
        }

        // 11. 보호막 흡수 / 디스펠 면역
        if raw.contains("흡수") || raw.contains("보호막") {
            hints.append("[보호막] 시간 내 피해 억제")
        }

        // SUG-1: 폴백 제거. 매칭 키워드 없으면 힌트 안 내보냄 (false negative > false positive).
        return hints
    }
}
