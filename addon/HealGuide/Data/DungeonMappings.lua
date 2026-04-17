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
addon.DungeonMappings.keyByMapID = {
    -- TODO: mapID 확인 — Magisters' Terrace (원본 585, Midnight 버전 재확인 필요)
    -- [585] = "MagistersTerrace",
    -- TODO: mapID 확인 — Pit of Saron (원본 632, Midnight 버전 재확인 필요)
    -- [632] = "PitOfSaron",
    -- TODO: mapID 확인 — Skyreach (원본 1209, Midnight 버전 재확인 필요)
    -- [1209] = "Skyreach",
    -- TODO: mapID 확인 — Seat of the Triumvirate (원본 1753, Midnight 버전 재확인 필요)
    -- [1753] = "SeatOfTriumvirate",
    -- TODO: mapID 확인 — Algeth'ar Academy (원본 2526, Midnight 버전 재확인 필요)
    -- [2526] = "AlgetharAcademy",
    -- TODO: mapID 확인 — Windrunner's Spire (신규 던전, PTR/라이브 확인 필요)
    -- TODO: mapID 확인 — Maisara Caverns (신규 던전, PTR/라이브 확인 필요)
    -- TODO: mapID 확인 — Nexus-Point X'enas (신규 던전, PTR/라이브 확인 필요)
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
