-- HealGuide 랭커 데이터 파일 (Option B 스키마)
-- Mac 앱이 실제 수집 후 이 파일을 덮어씁니다.
-- 현재 파일은 스키마 테스트용 더미 데이터입니다.

HGPT_RankerData = {
    entries = {
        {
            _meta = {
                version          = 1,
                collectedAt      = "2026-04-20T14:30:00+09:00",
                region           = "KR",
                dungeonID        = 2660,
                dungeonName      = "네룹아르 궁전",
                difficulty       = "Mythic",
                spec             = "DiscPriest",
                rankersRequested = 10,
                rankersUsed      = 8,
                talentFilter     = { preset = "Evangelism", stringMode = false, similarity = 0.0 },
            },
            data = {
                -- 네룹아르 궁전: 울그루가시 (encounterID 2902, 더미값)
                [2902] = {
                    -- bossSpellID 440802 → 힐러 스킬 추천
                    [440802] = {
                        { spellID = 33206, delay = 2.3, stddev = 0.4, count = 8, quorum = "8/8" },
                        { spellID = 47788, delay = 1.5, stddev = 0.6, count = 6, quorum = "6/8" },
                    },
                    -- bossSpellID 440917 → 힐러 스킬 추천
                    [440917] = {
                        { spellID = 62618, delay = 0.5, stddev = 0.2, count = 8, quorum = "8/8" },
                    },
                },
            },
        },
    },
}
