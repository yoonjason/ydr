import Foundation

// Midnight 시즌 1 M+ 던전 8개 전술 가이드 (사용자 큐레이션).
// 키: WCL DungeonInfo.id
// 값: 보스 배열 (WCL 영문명 기준 매칭)
enum TacticalGuideCatalog {

    /// 던전 ID 로 보스 가이드 목록 조회. 없으면 빈 배열.
    static func bossGuides(forDungeonID id: Int) -> [BossTacticalGuide] {
        guides[id] ?? []
    }

    /// WCL 영문 보스명 정규화 매칭. 정관사/대소문자/공백 차이 흡수.
    /// 1차: 정확 일치 — 2차: substring 양방향 contains (수식어 생략 케이스 방어).
    /// 예: WCL "Garfrost" ↔ catalog "Forgemaster Garfrost" — 후자가 전자를 contains.
    static func bossGuide(forDungeonID id: Int, englishBossName: String) -> BossTacticalGuide? {
        let target = normalize(englishBossName)
        guard let list = guides[id], !list.isEmpty else { return nil }
        if let exact = list.first(where: { normalize($0.englishBossName) == target }) {
            return exact
        }
        return list.first { guide in
            let cat = normalize(guide.englishBossName)
            return cat.contains(target) || target.contains(cat)
        }
    }

    /// 특정 bossSpellID 의 한국어 스킬명 과 매칭되는 전술 라인(들) 반환.
    /// 한 스킬이 여러 라인에 등장 가능 (예: '억제 지대' 가 2줄에 언급됨).
    /// SUGGESTION-2: substring fuzzy 매칭은 최소 3글자 이상에서만 허용.
    /// 2글자 이하 ('보주' 등) 은 여러 스킬 공통 단어라 false positive 유발 → 정확 일치만.
    static func matchingLines(
        dungeonID: Int,
        englishBossName: String,
        spellKoreanName: String
    ) -> [TacticalLine] {
        guard let bossGuide = bossGuide(forDungeonID: dungeonID, englishBossName: englishBossName) else {
            return []
        }
        let minFuzzyLength = 3
        return bossGuide.lines.filter { line in
            guard !line.abilityName.isEmpty else { return false }
            // 정확 일치는 항상 허용
            if line.abilityName == spellKoreanName { return true }
            // 짧은 이름 (2글자 이하) 은 정확 일치만 — substring 은 과매칭 위험
            let shorter = min(line.abilityName.count, spellKoreanName.count)
            guard shorter >= minFuzzyLength else { return false }
            return spellKoreanName.contains(line.abilityName)
                || line.abilityName.contains(spellKoreanName)
        }
    }

    /// 특정 보스의 '일반 주의사항' (스킬 지정 없는 note/critical 라인). UI 에 '보스 전체' 섹션으로 표시.
    static func generalLines(dungeonID: Int, englishBossName: String) -> [TacticalLine] {
        guard let bossGuide = bossGuide(forDungeonID: dungeonID, englishBossName: englishBossName) else {
            return []
        }
        return bossGuide.lines.filter { $0.abilityName.isEmpty }
    }

    private static func normalize(_ raw: String) -> String {
        let lower = raw.lowercased()
        let stripped: String
        if lower.hasPrefix("the ") {
            stripped = String(lower.dropFirst(4))
        } else if lower.hasPrefix("an ") {
            stripped = String(lower.dropFirst(3))
        } else if lower.hasPrefix("a ") {
            stripped = String(lower.dropFirst(2))
        } else {
            stripped = lower
        }
        return stripped.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Catalog

    private static let guides: [Int: [BossTacticalGuide]] = [
        // 공결탑 제나스 (WCL 12915)
        12915: nexusPointXenas,
        // 마법학자의 정원 (WCL 12811)
        12811: magistersTerrace,
        // 마이사라 동굴 (WCL 12874)
        12874: maisaraCaverns,
        // 윈드러너 첨탑 (WCL 12805)
        12805: windrunnerSpire,
        // 알게타르 대학 (WCL 112526)
        112526: algetharAcademy,
        // 삼두정의 권좌 (WCL 361753)
        361753: seatOfTheTriumvirate,
        // 하늘탑 (WCL 61209)
        61209: skyreach,
        // 사론의 구덩이 (WCL 10658)
        10658: pitOfSaron,
    ]

    // MARK: - 공결탑 제나스

    private static let nexusPointXenas: [BossTacticalGuide] = [
        BossTacticalGuide(englishBossName: "Karesh", koreanBossName: "카스레스", lines: [
            TacticalLine(priority: .critical, abilityName: "역류 돌진",
                         action: "비전 광선 제거 (많은 선이 교차되는 지점에서 한꺼번에 제거 가능)"),
            TacticalLine(priority: .note, abilityName: "핵심불꽃 폭발",
                         action: "기력 100 시전. 밀쳐내기 + 바닥 주의"),
        ]),
        BossTacticalGuide(englishBossName: "Nisara", koreanBossName: "니사라", lines: [
            TacticalLine(priority: .critical, abilityName: "빛흉터 섬광",
                         action: "바닥 안에 들어가서 힐/딜 (NPC가 돌진하기 전 범위 진입 금지)"),
            TacticalLine(priority: .important, abilityName: "",
                         action: "쫄 빠르게 정리하기"),
        ]),
        BossTacticalGuide(englishBossName: "Lothlaxion", koreanBossName: "로스락시온", lines: [
            TacticalLine(priority: .critical, abilityName: "찬란한 분산",
                         action: "분신이 진행 방향에 서지 않도록 주의"),
            TacticalLine(priority: .critical, abilityName: "천상의 기만",
                         action: "뿔 안 달린 본체 찾아서 차단하기"),
        ]),
    ]

    // MARK: - 마법학자의 정원

    private static let magistersTerrace: [BossTacticalGuide] = [
        BossTacticalGuide(englishBossName: "Arcanotron Custos", koreanBossName: "쿠스토스", lines: [
            TacticalLine(priority: .critical, abilityName: "연료 보급 프로토콜",
                         action: "보주 나눠서 먹기 (보스 받는 피해 증가)"),
            TacticalLine(priority: .note, abilityName: "비전 방출",
                         action: "밀쳐내기 주의"),
        ]),
        BossTacticalGuide(englishBossName: "Seranel Sunlash", koreanBossName: "선래쉬", lines: [
            TacticalLine(priority: .critical, abilityName: "룬 징표",
                         action: "대상자는 <억제 지대> 안에 들어가서 차례대로 제거 (디버프 확인)"),
            TacticalLine(priority: .critical, abilityName: "침묵의 물결",
                         action: "기력 100 시전 전에 <억제 지대> 들어가기"),
            TacticalLine(priority: .critical, abilityName: "억제 지대",
                         action: "룬 징표 / 침묵의 물결 대응 지점"),
        ]),
        BossTacticalGuide(englishBossName: "Gemellus", koreanBossName: "제멜루스", lines: [
            TacticalLine(priority: .critical, abilityName: "신경 연결",
                         action: "캐릭터 발 밑 화살표 확인 후 해당 보스에게 접촉"),
            TacticalLine(priority: .note, abilityName: "천공의 손아귀",
                         action: "끌어당겨지지 않도록 주의"),
        ]),
        BossTacticalGuide(englishBossName: "Degentrius", koreanBossName: "디젠트리우스", lines: [
            TacticalLine(priority: .critical, abilityName: "",
                         action: "공간을 4곳으로 분리, 흩어져서 서기"),
            TacticalLine(priority: .critical, abilityName: "불안정한 공허의 정수",
                         action: "떨어지는 구슬 받아주기"),
            TacticalLine(priority: .note, abilityName: "엔트로피 포식",
                         action: "퍼지는 보주 조심하기"),
        ]),
    ]

    // MARK: - 마이사라 동굴

    private static let maisaraCaverns: [BossTacticalGuide] = [
        BossTacticalGuide(englishBossName: "Muro'jin and Nekraxx", koreanBossName: "무로진과 네크락스", lines: [
            TacticalLine(priority: .critical, abilityName: "",
                         action: "생명력 맞춰서 잡기"),
            TacticalLine(priority: .critical, abilityName: "썩어가는 강하",
                         action: "대상자는 얼음 덫 밟기 (이외에는 덫 밟지 말기)"),
            TacticalLine(priority: .important, abilityName: "탄막",
                         action: "대상자 혼자 서기"),
        ]),
        BossTacticalGuide(englishBossName: "Vordaza", koreanBossName: "보르다자", lines: [
            TacticalLine(priority: .critical, abilityName: "악령 왜곡",
                         action: "악령끼리 부딪히게 유도해서 제거 (디버프 확인하고 순서대로 터뜨리기, 군중 제어 활용 가능)"),
            TacticalLine(priority: .note, abilityName: "괴저의 수렴",
                         action: "구슬 주의하며 구슬 제거하기"),
        ]),
        BossTacticalGuide(englishBossName: "Rak'tul, Vessel of Souls", koreanBossName: "락툴", lines: [
            TacticalLine(priority: .critical, abilityName: "영혼 분쇄하기",
                         action: "가능한 토템끼리 거리 멀지 않게 보스 유도, 토템 빠르게 제거"),
            TacticalLine(priority: .important, abilityName: "영혼을 찢는 포효",
                         action: "보스 구역까지 빠르게 이동 (영혼 많이 차단할수록 좋음, 체력 신경)"),
        ]),
    ]

    // MARK: - 윈드러너 첨탑

    private static let windrunnerSpire: [BossTacticalGuide] = [
        BossTacticalGuide(englishBossName: "Emberdawn", koreanBossName: "잿불여명", lines: [
            TacticalLine(priority: .important, abilityName: "불타는 강풍",
                         action: "외곽에 깔기"),
            TacticalLine(priority: .note, abilityName: "",
                         action: "브레스, 회오리 주의"),
        ]),
        BossTacticalGuide(englishBossName: "Derelict Duo", koreanBossName: "버려진 2인조", lines: [
            TacticalLine(priority: .critical, abilityName: "쇠약의 저주",
                         action: "이 디버프 때 <힘껏 당기기> 갈고리를 칼리스(유령)에게 유도"),
            TacticalLine(priority: .critical, abilityName: "힘껏 당기기",
                         action: "쇠약의 저주 대상자에게 사용해 칼리스(유령)로 유도"),
            TacticalLine(priority: .important, abilityName: "어둠의 저주",
                         action: "영혼 메즈 또는 저주 해제"),
            TacticalLine(priority: .important, abilityName: "흩어지는 분출",
                         action: "최대한 뭉쳐서 깔기"),
        ]),
        BossTacticalGuide(englishBossName: "Commander Kroluk", koreanBossName: "크롤루크", lines: [
            TacticalLine(priority: .critical, abilityName: "재집결의 고함",
                         action: "쫄 먼저 처리하기"),
            TacticalLine(priority: .critical, abilityName: "위협의 외침",
                         action: "도약 때만 약산개했다가 최소 2명이 뭉쳐서 공포 저항하기"),
        ]),
        BossTacticalGuide(englishBossName: "The Restless Heart", koreanBossName: "잠 못 드는 심장", lines: [
            TacticalLine(priority: .critical, abilityName: "백발백중 바람작렬",
                         action: "고리 퍼지기 전에 화살 밟아 피하기"),
            TacticalLine(priority: .critical, abilityName: "돌풍 도약",
                         action: "디버프 화살 밟고 제거"),
            TacticalLine(priority: .critical, abilityName: "돌풍 사격",
                         action: "화살 밟아 생긴 바닥 제거 가능"),
        ]),
    ]

    // MARK: - 알게타르 대학

    private static let algetharAcademy: [BossTacticalGuide] = [
        BossTacticalGuide(englishBossName: "Vexamus", koreanBossName: "벡사무스", lines: [
            TacticalLine(priority: .critical, abilityName: "비전 보주",
                         action: "나눠서 먹기"),
            TacticalLine(priority: .important, abilityName: "마나 폭탄",
                         action: "바닥 외곽에 깔기"),
            TacticalLine(priority: .note, abilityName: "비전 균열",
                         action: "기력 100 시전. 바닥 주의하기"),
        ]),
        BossTacticalGuide(englishBossName: "Overgrown Ancient", koreanBossName: "비대해진 고대정령", lines: [
            TacticalLine(priority: .critical, abilityName: "발아",
                         action: "한 점에 뭉쳐서 같은 방향으로 돌며 씨앗 깔기"),
            TacticalLine(priority: .critical, abilityName: "",
                         action: "쫄은 빠르게 제거하기"),
            TacticalLine(priority: .critical, abilityName: "",
                         action: "출혈 디버프: 나무가 생성하는 바닥 안에 들어가서 지우기"),
        ]),
        BossTacticalGuide(englishBossName: "Crawth", koreanBossName: "크로스", lines: [
            TacticalLine(priority: .critical, abilityName: "",
                         action: "정해진 골대 먼저 공 3개씩 넣어 활성화"),
            TacticalLine(priority: .important, abilityName: "귀청 터질듯한 비명",
                         action: "시전 전에 주문 시전 끊기"),
        ]),
        BossTacticalGuide(englishBossName: "Echo of Doragosa", koreanBossName: "도라고사의 메아리", lines: [
            TacticalLine(priority: .critical, abilityName: "압도적인 힘",
                         action: "3중첩 시 바닥 생성. 2중첩 시 미리 바닥 깔 준비하기"),
            TacticalLine(priority: .note, abilityName: "",
                         action: "바닥에서 방출되는 보주 주의하기"),
        ]),
    ]

    // MARK: - 삼두정의 권좌

    private static let seatOfTheTriumvirate: [BossTacticalGuide] = [
        BossTacticalGuide(englishBossName: "Zuraal the Ascended", koreanBossName: "주라알", lines: [
            TacticalLine(priority: .critical, abilityName: "척살",
                         action: "도약 외곽으로 유도하기"),
            TacticalLine(priority: .critical, abilityName: "수액 격돌",
                         action: "쫄 빠르게 제거하기"),
        ]),
        BossTacticalGuide(englishBossName: "Saprish", koreanBossName: "사프리쉬", lines: [
            TacticalLine(priority: .critical, abilityName: "위상 질주",
                         action: "공허 폭탄을 유도해서 제거하기"),
            TacticalLine(priority: .critical, abilityName: "과부하",
                         action: "시전 전에 폭탄 모두 제거하기"),
            TacticalLine(priority: .critical, abilityName: "섬뜩한 비명",
                         action: "차단 필수"),
        ]),
        BossTacticalGuide(englishBossName: "Viceroy Nezhar", koreanBossName: "네자르", lines: [
            TacticalLine(priority: .critical, abilityName: "공허의 폭풍",
                         action: "기력 100 시. 보스가 있는 곳으로 빠르게 이동"),
            TacticalLine(priority: .note, abilityName: "정신의 채찍",
                         action: "함께 이동하며 촉수 제거하기"),
        ]),
        BossTacticalGuide(englishBossName: "L'ura", koreanBossName: "르우라", lines: [
            TacticalLine(priority: .critical, abilityName: "불협의 광선",
                         action: "대상자 음표 방향으로 이동해서 음표 적중시키기"),
            TacticalLine(priority: .critical, abilityName: "",
                         action: "알레리아가 보스 기절시키면 받는 피해 대폭 증가"),
            TacticalLine(priority: .important, abilityName: "암울한 합창",
                         action: "음표 주변 조심하기"),
        ]),
    ]

    // MARK: - 하늘탑

    private static let skyreach: [BossTacticalGuide] = [
        BossTacticalGuide(englishBossName: "Ranjit", koreanBossName: "란지트", lines: [
            TacticalLine(priority: .critical, abilityName: "강풍의 쇄도",
                         action: "대상자 밀쳐지니 낙사 주의"),
            TacticalLine(priority: .important, abilityName: "바람 차크람",
                         action: "이동 경로에 서지 않도록 주의"),
            TacticalLine(priority: .note, abilityName: "회전 표창의 회오리",
                         action: "폭풍 밟지 않도록 조심"),
        ]),
        BossTacticalGuide(englishBossName: "Araknath", koreanBossName: "아라크나스", lines: [
            TacticalLine(priority: .critical, abilityName: "충전",
                         action: "외부의 빛줄기 몸으로 막기"),
            TacticalLine(priority: .important, abilityName: "열기 피로",
                         action: "전방 조심, 빛줄기 재생성 시 막아주기"),
        ]),
        BossTacticalGuide(englishBossName: "Rukhran", koreanBossName: "루크란", lines: [
            TacticalLine(priority: .critical, abilityName: "태양의 도래",
                         action: "쫄 대상자 멀리 도망치기"),
            TacticalLine(priority: .critical, abilityName: "타오르는 깃털",
                         action: "중앙 기둥 뒤에 숨기 (보스 시야에 안 보이게)"),
        ]),
        BossTacticalGuide(englishBossName: "High Sage Viryx", koreanBossName: "비릭스", lines: [
            TacticalLine(priority: .critical, abilityName: "렌즈 반사광",
                         action: "외곽에서 바닥 유도"),
            TacticalLine(priority: .critical, abilityName: "",
                         action: "플레이어 납치 시 쫄 빠르게 제거"),
        ]),
    ]

    // MARK: - 사론의 구덩이

    private static let pitOfSaron: [BossTacticalGuide] = [
        BossTacticalGuide(englishBossName: "Forgemaster Garfrost", koreanBossName: "가프로스트", lines: [
            TacticalLine(priority: .critical, abilityName: "사로나이트 던지기",
                         action: "보스 근처로 이동하기"),
            TacticalLine(priority: .critical, abilityName: "빙하 과잉",
                         action: "설치된 사로나이트 뒤에 숨기"),
        ]),
        BossTacticalGuide(englishBossName: "Ick and Krick", koreanBossName: "이크와 크리크", lines: [
            TacticalLine(priority: .critical, abilityName: "망령의 이동",
                         action: "망령 빠르게 제거하기"),
            TacticalLine(priority: .critical, abilityName: "죽음의 화살",
                         action: "차단하기"),
            TacticalLine(priority: .important, abilityName: "육중한 집착",
                         action: "대상자는 도망가면서 싸우기"),
        ]),
        BossTacticalGuide(englishBossName: "Scourgelord Tyrannus", koreanBossName: "티라누스", lines: [
            TacticalLine(priority: .critical, abilityName: "서릿발 작렬",
                         action: "마력 깃든 뼈 무더기로 이동"),
            TacticalLine(priority: .critical, abilityName: "사자의 군대",
                         action: "쫄 빠르게 제거"),
            TacticalLine(priority: .note, abilityName: "해골 주입",
                         action: "뼈 무더기에 마력 깃들게 함"),
        ]),
    ]
}
