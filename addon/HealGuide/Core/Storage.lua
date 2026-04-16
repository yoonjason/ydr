local addonName, addon = ...
addon.Storage = {}
local Storage = addon.Storage

local DEFAULT_SETTINGS = {
    soundEnabled    = true,
    alertMode       = "reactive",
    alertFramePoint = { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 },
    displaySeconds  = 2.0,
    locked          = false,
    showSpellName   = false,
    iconBaseSize    = 64,
    iconPulseSize   = 96,
    ttsEnabled      = false,
    ttsVoiceID      = 0,
    ttsRate         = 5,
    ttsVolume       = 100,
    leadTime        = 1.5,
    debugMode       = false,
    conditionFallback = true,  -- 조건 평가 실패 시 true=발화, false=스킵
}

function Storage:Init()
    HealGuideCharDB = HealGuideCharDB or {}
    local db = HealGuideCharDB

    db.version        = db.version        or 1
    db.dungeons       = db.dungeons       or {}
    db.encounterIndex = db.encounterIndex or {}
    db.settings       = db.settings       or {}

    -- 마이그레이션은 DEFAULT_SETTINGS 주입 이전에 실행해야 함.
    -- 이후에 돌리면 DEFAULT 가 새 키를 이미 채워버려 `not db.settings.alertFramePoint`
    -- 가드가 항상 false 가 되어 구버전 위치가 유실된다.

    -- 구버전 framePosition → alertFramePoint 마이그레이션
    if db.settings.framePosition and not db.settings.alertFramePoint then
        local old = db.settings.framePosition
        db.settings.alertFramePoint = {
            point = "CENTER", relPoint = "CENTER",
            x = old.x or 0, y = old.y or 200,
        }
        db.settings.framePosition = nil
    end

    -- 구버전 iconSize → iconBaseSize / iconPulseSize 마이그레이션
    if db.settings.iconSize ~= nil then
        local old = db.settings.iconSize
        db.settings.iconBaseSize  = old
        db.settings.iconPulseSize = math.floor(old * 1.5)
        db.settings.iconSize      = nil
    end

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
                    leadIns   = bossData.leadIns   or {},
                },
            },
        }
    end

    db.dungeons[dungeonKey] = entry
    self:RebuildEncounterIndex()
    return dungeonKey
end

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
            leadIns   = bossData.leadIns   or {},
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
