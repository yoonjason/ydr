-- HealGuide Data
-- 이 파일은 HealGuide macOS 앱으로 생성한 HGPT_Data 를 붙여넣는 자리입니다.
-- 아래 예시를 실제 데이터로 교체하세요.
--
-- 포맷:
--   HGPT_Data[<SpecKey>][<encounterID>][<bossSpellID>] = {
--     { spellID = <playerSpellID>, delay = <seconds> },
--     ...
--   }
--
-- SpecKey: "DiscPriest", "HolyPriest", "RestoDruid",
--          "MistweaverMonk", "HolyPaladin", "RestoShaman", "PresEvoker"
--
-- spellID / bossSpellID: Blizzard spell ID (숫자)
-- delay: 보스 스킬 시전 후 해당 힐을 쓰기까지의 지연 (초, 소수점 허용)

HGPT_Data = HGPT_Data or {}

-- 예시 — 실제 앱이 생성한 데이터로 교체 필요
HGPT_Data["DiscPriest"] = HGPT_Data["DiscPriest"] or {}
HGPT_Data["DiscPriest"][2900] = {  -- 예시 encounterID
    [444444] = {  -- 예시 보스 스킬 ID
        { spellID = 17,    delay = 0.5 },   -- Power Word: Shield
        { spellID = 33076, delay = 2.3 },   -- Prayer of Mending
    },
}
