local addonName, addon = ...
addon.Storage = {}
local Storage = addon.Storage

local DEFAULT_SETTINGS = {
    soundEnabled = true,
    alertMode    = "reactive",
    framePosition = { x = 0, y = 200 },
    displaySeconds = 2.0,
    locked = false,
}

function Storage:Init()
    HealGuideCharDB = HealGuideCharDB or {}
    local db = HealGuideCharDB

    db.version      = db.version      or 1
    db.dungeons     = db.dungeons     or {}
    db.encounterIndex = db.encounterIndex or {}
    db.settings     = db.settings     or {}

    for k, v in pairs(DEFAULT_SETTINGS) do
        if db.settings[k] == nil then
            db.settings[k] = v
        end
    end

    self:RebuildEncounterIndex()
end

function Storage:RebuildEncounterIndex()
    local db = HealGuideCharDB
    db.encounterIndex = {}

    for dungeonKey, dungeon in pairs(db.dungeons) do
        if dungeon.enabled then
            for encounterID in pairs(dungeon.bosses) do
                db.encounterIndex[encounterID] = {
                    dungeonKey = dungeonKey,
                    enabled    = true,
                }
            end
        end
    end
end

-- importData: validated table from ImportParser
-- 같은 dungeonKey가 없으면 신규 생성. 스펙은 덮어씌우지 않고 병합.
function Storage:AddDungeon(importData)
    local db = HealGuideCharDB
    local dungeonKey = importData.dungeonName .. "_" .. tostring(time())

    local entry = {
        displayName  = importData.dungeonName,
        originalName = importData.dungeonName,
        sourceURL    = importData.sourceURL or "",
        importedAt   = time(),
        enabled      = true,
        bosses       = {},
    }

    for encounterID, bossData in pairs(importData.bosses) do
        entry.bosses[encounterID] = {
            name     = bossData.name,
            duration = bossData.duration,
            specs    = {
                [importData.spec] = {
                    timeline  = bossData.timeline  or {},
                    reactions = bossData.reactions or {},
                },
            },
        }
    end

    db.dungeons[dungeonKey] = entry
    self:RebuildEncounterIndex()
    return dungeonKey
end

-- 기존 dungeonKey 에 새 스펙 데이터를 병합 (갱신)
function Storage:UpdateDungeon(dungeonKey, importData)
    local db = HealGuideCharDB
    local dungeon = db.dungeons[dungeonKey]
    if not dungeon then return false end

    for encounterID, bossData in pairs(importData.bosses) do
        if not dungeon.bosses[encounterID] then
            dungeon.bosses[encounterID] = {
                name     = bossData.name,
                duration = bossData.duration,
                specs    = {},
            }
        end
        dungeon.bosses[encounterID].specs[importData.spec] = {
            timeline  = bossData.timeline  or {},
            reactions = bossData.reactions or {},
        }
    end

    self:RebuildEncounterIndex()
    return true
end

function Storage:RemoveDungeon(dungeonKey)
    local db = HealGuideCharDB
    if db.dungeons[dungeonKey] then
        db.dungeons[dungeonKey] = nil
        self:RebuildEncounterIndex()
        return true
    end
    return false
end

function Storage:SetDungeonEnabled(dungeonKey, enabled)
    local db = HealGuideCharDB
    if db.dungeons[dungeonKey] then
        db.dungeons[dungeonKey].enabled = enabled
        self:RebuildEncounterIndex()
        return true
    end
    return false
end

function Storage:SetDungeonDisplayName(dungeonKey, name)
    local db = HealGuideCharDB
    if db.dungeons[dungeonKey] then
        db.dungeons[dungeonKey].displayName = name
        return true
    end
    return false
end

function Storage:GetDungeons()
    return HealGuideCharDB.dungeons
end

function Storage:GetDungeon(dungeonKey)
    return HealGuideCharDB.dungeons[dungeonKey]
end

-- encounterID 로 보스 데이터 + 소속 dungeonKey 반환
function Storage:GetEncounterData(encounterID)
    local db = HealGuideCharDB
    local entry = db.encounterIndex[encounterID]
    if not entry then return nil, nil end

    local dungeon = db.dungeons[entry.dungeonKey]
    if not dungeon or not dungeon.enabled then return nil, nil end

    return dungeon.bosses[encounterID], entry.dungeonKey
end

function Storage:GetSetting(key)
    return HealGuideCharDB.settings[key]
end

function Storage:SetSetting(key, value)
    HealGuideCharDB.settings[key] = value
end
