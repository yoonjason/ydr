local addonName, addon = ...
addon.DungeonMappings = {}
local DungeonMappings = addon.DungeonMappings

-- M+ 참여 던전의 CM mapID → HealGuide dungeonKey 매핑.
-- 누적형: 한 번 추가하면 시즌/확장팩 관계없이 계속 사용.
-- 신규 던전이 M+ 풀에 등장할 때만 엔트리 추가.
-- mapID 는 GetInstanceInfo() 4번째 반환값 또는 C_ChallengeMode.GetMapTable/GetMapUIInfo 참조.

-- Midnight Season 1 M+ 던전 CM mapID → dungeonKey 매핑
-- mapID = GetInstanceInfo() 4번째 반환값 (instanceMapID)
-- 확인 방법: wowhead 던전 저널 / warcraft.wiki.gg / 인게임 /run print(select(8,GetInstanceInfo()))
-- mapID 출처: BigWigsMods/BigWigs Loader.lua currentSeason 테이블 (2026-04-17 확인)
--   https://github.com/BigWigsMods/BigWigs/blob/master/Loader.lua
--   legacy 4종은 warcraft.wiki.gg/wiki/InstanceID 와 교차 검증 완료
addon.DungeonMappings.keyByMapID = {
    [2811] = "MagistersTerrace",   -- Midnight 리부트 인스턴스 (BC 원본 585 와는 별도)
    [658]  = "PitOfSaron",         -- WotLK 원본 재편입 (기존 주석 632 는 오류였음)
    [1209] = "Skyreach",           -- WoD 원본 재편입
    [1753] = "SeatOfTriumvirate",  -- Legion 원본 재편입
    [2526] = "AlgetharAcademy",    -- Dragonflight 원본 재편입
    [2805] = "WindrunnerSpire",    -- Midnight 신규
    [2874] = "MaisaraCaverns",     -- Midnight 신규
    [2915] = "NexusPointXenas",    -- Midnight 신규
}

-- 현재 시즌 M+ 로스터를 Blizzard API 로 조회해 keyByMapID 미매핑 던전을 dprint 로 고지.
-- 매 PLAYER_LOGIN 에서 1회 호출. 시즌 갱신 감지용.
function DungeonMappings:ValidateActiveSeason()
    if not C_ChallengeMode or not C_ChallengeMode.GetMapTable then return end
    local ok, mapIDs = pcall(C_ChallengeMode.GetMapTable)
    if not ok or type(mapIDs) ~= "table" then return end

    local missing = {}
    for _, mapID in ipairs(mapIDs) do
        if not self.keyByMapID[mapID] then
            local name
            if C_ChallengeMode.GetMapUIInfo then
                local ok2, uiName = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
                if ok2 and type(uiName) == "string" then name = uiName end
            end
            table.insert(missing, string.format("mapID=%d (%s)", mapID, name or "?"))
        end
    end

    if #missing > 0 then
        addon.dprint(string.format(
            "DungeonMappings.keyByMapID 에 현재 시즌 던전 %d개 미등록: %s",
            #missing, table.concat(missing, ", ")))
    end
end
