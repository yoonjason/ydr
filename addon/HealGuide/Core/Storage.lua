local addonName, addon = ...
addon.Storage = {}
local Storage = addon.Storage

-- ── AceDB 스키마 ──────────────────────────────────────────────────────────────

local DEFAULTS = {
    global  = { _charDbMigratedV2 = false },
    profile = {
        version  = 2,
        dungeons = {},
        settings = {
            soundEnabled      = true,
            alertMode         = "reactive",
            alertFramePoint   = { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 },
            displaySeconds    = 2.0,
            locked            = false,
            showSpellName     = false,
            iconBaseSize      = 64,
            iconPulseSize     = 96,
            ttsEnabled        = false,
            ttsVoiceID        = 0,
            ttsRate           = 5,
            ttsVolume         = 100,
            leadTime          = 1.5,
            debugMode         = false,
            conditionFallback = true,
            keystoneMinLevel  = 2,
            alertSoundID      = 888,
            minimapAngle      = 220,
            alertFrameEnabled = true,
            alertFrameSlots   = 1,
            timelineVisible      = true,
            timelineOrientation  = "horizontal",
            timelineWindow       = 30,
            timelineIconSize     = 36,
            timelineTrackLength  = 400,
            timelineShowTicks    = true,
            timelineLocked       = false,
            timelinePoint        = { point = "CENTER", relPoint = "CENTER", x = 0, y = -200 },
            -- Phase 4a: 테마
            alertBgColor   = { r = 0,   g = 0,   b = 0,   a = 0.75 },
            alertTextColor = { r = 1,   g = 1,   b = 1,   a = 1.0  },
            alertFontName  = "Friz Quadrata TT",
            alertFontSize  = 14,
            alertSoundName = "ReadyCheck",
            -- Phase 5α: 랭커 데이터 정책 (off | merge | exclusive)
            rankerPolicy   = "merge",
            -- Phase 5α 베타: 쿨타임 fallback. 추천 스킬이 쿨이면 같은 카테고리 내 다음
            -- 순위 스킬 또는 다른 사용 가능 스킬로 대체. DiscPriest/HolyPriest 에 한해
            -- 카테고리 태깅 제공됨. 기본값 off — 기존 동작 유지.
            useBetaCooldownFallback = false,
        },
    },
}

-- ── 내부 상태 ─────────────────────────────────────────────────────────────────

local db              = nil
local encounterIndex  = {}  -- 파생 인덱스 (영속화하지 않음, 로드 시 재빌드)

-- ── Init ─────────────────────────────────────────────────────────────────────

function Storage:Init()
    local AceDB = LibStub("AceDB-3.0")
    db = AceDB:New("HealGuideDB", DEFAULTS, true)

    -- LibDualSpec 연동: PLAYER_LOGIN 이후(charKey 확정 후)에 호출해야 안전.
    -- Init 시점(ADDON_LOADED)에는 UnitName("player") 이 nil일 수 있어 db.charKey 가 nil.
    -- Storage:InitDualSpec() 을 PLAYER_LOGIN 핸들러에서 호출할 것.

    -- 구버전 캐릭터별 SavedVariable 에서 현재 프로파일로 1회 마이그레이션
    self:_MigrateFromCharDB()

    -- useRankerData(bool) → rankerPolicy(string) 1회 마이그레이션
    local s = db.profile.settings
    if s.useRankerData ~= nil then
        s.rankerPolicy  = s.useRankerData and "merge" or "off"
        s.useRankerData = nil
    end

    -- 프로파일 전환 콜백: UI 갱신
    db.RegisterCallback(self, "OnProfileChanged", function(target, event, database, newProfile)
        target:RebuildEncounterIndex()
        if addon.EncounterEngine and addon.EncounterEngine.OnEncounterEnd then
            addon.EncounterEngine:OnEncounterEnd()
        end
        if addon.MainFrame then
            if addon.MainFrame._RefreshSettings then addon.MainFrame:_RefreshSettings() end
            if addon.MainFrame._RefreshDataTab  then addon.MainFrame:_RefreshDataTab()  end
        end
        if addon.AlertFrame and addon.AlertFrame.ApplyTheme then
            addon.AlertFrame:ApplyTheme()
        end
        if addon.TimelineFrame and addon.TimelineFrame.ApplyTheme then
            addon.TimelineFrame:ApplyTheme()
        end
    end)

    db.RegisterCallback(self, "OnProfileReset", function(target, event, database, profileName)
        target:RebuildEncounterIndex()
        if addon.EncounterEngine and addon.EncounterEngine.OnEncounterEnd then
            addon.EncounterEngine:OnEncounterEnd()
        end
        if addon.MainFrame and addon.MainFrame._RefreshSettings then
            addon.MainFrame:_RefreshSettings()
        end
        if addon.AlertFrame and addon.AlertFrame.ApplyTheme then
            addon.AlertFrame:ApplyTheme()
        end
        if addon.TimelineFrame and addon.TimelineFrame.ApplyTheme then
            addon.TimelineFrame:ApplyTheme()
        end
    end)

    self:RebuildEncounterIndex()
end

-- PLAYER_LOGIN 이후 호출 — charKey 가 확정된 시점에 EnhanceDatabase 실행
function Storage:InitDualSpec()
    if not db then return end
    if not db.charKey then return end  -- 만약에도 nil이면 조용히 스킵
    local LibDualSpec = LibStub("LibDualSpec-1.0", true)
    if LibDualSpec then
        LibDualSpec:EnhanceDatabase(db, "HealGuide")
    end
end

-- ── 마이그레이션 ──────────────────────────────────────────────────────────────

function Storage:_MigrateFromCharDB()
    if db.global._charDbMigratedV2 then return end
    if type(HealGuideCharDB) ~= "table" then
        db.global._charDbMigratedV2 = true
        return
    end

    local charDB = HealGuideCharDB

    if type(charDB.settings) == "table" then
        local settings = charDB.settings

        -- 구버전 키 마이그레이션 (charDB 내에서 먼저 처리)
        if settings.framePosition and not settings.alertFramePoint then
            local old = settings.framePosition
            settings.alertFramePoint = { point = "CENTER", relPoint = "CENTER", x = old.x or 0, y = old.y or 200 }
            settings.framePosition   = nil
        end
        if settings.iconSize ~= nil then
            local old = settings.iconSize
            settings.iconBaseSize  = old
            settings.iconPulseSize = math.floor(old * 1.5)
            settings.iconSize      = nil
        end
        if settings.timerBarPoint and not settings.timelinePoint then
            settings.timelinePoint       = settings.timerBarPoint
            settings.timelineOrientation = "vertical"
            settings.timerBarPoint       = nil
        end

        -- 기존 HealGuideCharDB 값을 우선하되, DEFAULTS 에 정의된 키만 허용
        for k, v in pairs(settings) do
            if DEFAULTS.profile.settings[k] ~= nil then
                db.profile.settings[k] = v
            end
        end
    end

    if type(charDB.dungeons) == "table" then
        for k, v in pairs(charDB.dungeons) do
            if not db.profile.dungeons[k] then
                db.profile.dungeons[k] = v
            end
        end
    end

    db.global._charDbMigratedV2 = true
end

-- ── 프로파일 API ──────────────────────────────────────────────────────────────

function Storage:GetCurrentProfile()
    return db:GetCurrentProfile()
end

function Storage:GetProfiles()
    return db:GetProfiles()
end

function Storage:SetProfile(name)
    db:SetProfile(name)
    -- RebuildEncounterIndex는 OnProfileChanged 콜백에서 처리
end

function Storage:CreateProfile(name)
    db:SetProfile(name)  -- 존재하지 않으면 AceDB가 빈 프로파일로 생성
end

function Storage:CopyFromProfile(fromName)
    db:CopyProfile(fromName)
    self:RebuildEncounterIndex()
end

function Storage:DeleteProfile(name)
    db:DeleteProfile(name)
end

function Storage:ResetProfile()
    db:ResetProfile()
    -- RebuildEncounterIndex는 OnProfileReset 콜백에서 처리
end

function Storage:RegisterProfileCallback(target, event, handler)
    db.RegisterCallback(target, event, handler)
end

function Storage:GetDB()
    return db
end

-- ── 던전 인덱스 ───────────────────────────────────────────────────────────────

function Storage:RebuildEncounterIndex()
    encounterIndex = {}
    local dungeons = db.profile.dungeons
    for dungeonKey, dungeon in pairs(dungeons) do
        if dungeon.enabled then
            for encounterID in pairs(dungeon.bosses) do
                encounterIndex[encounterID] = {
                    dungeonKey = dungeonKey,
                    enabled    = true,
                }
            end
        end
    end
end

-- ── 던전 CRUD ────────────────────────────────────────────────────────────────

function Storage:AddDungeon(importData)
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
    db.profile.dungeons[dungeonKey] = entry
    self:RebuildEncounterIndex()
    return dungeonKey
end

function Storage:UpdateDungeon(dungeonKey, importData)
    local dungeon = db.profile.dungeons[dungeonKey]
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
    if db.profile.dungeons[dungeonKey] then
        db.profile.dungeons[dungeonKey] = nil
        self:RebuildEncounterIndex()
        return true
    end
    return false
end

function Storage:SetDungeonEnabled(dungeonKey, enabled)
    if db.profile.dungeons[dungeonKey] then
        db.profile.dungeons[dungeonKey].enabled = enabled
        self:RebuildEncounterIndex()
        return true
    end
    return false
end

function Storage:SetDungeonDisplayName(dungeonKey, name)
    if db.profile.dungeons[dungeonKey] then
        db.profile.dungeons[dungeonKey].displayName = name
        return true
    end
    return false
end

function Storage:GetDungeons()
    return db.profile.dungeons
end

function Storage:GetDungeon(dungeonKey)
    return db.profile.dungeons[dungeonKey]
end

function Storage:GetEncounterData(encounterID)
    local entry = encounterIndex[encounterID]
    if not entry then return nil, nil end
    local dungeon = db.profile.dungeons[entry.dungeonKey]
    if not dungeon or not dungeon.enabled then return nil, nil end
    return dungeon.bosses[encounterID], entry.dungeonKey
end

-- ── 설정 API (호출부 무수정 유지) ────────────────────────────────────────────

function Storage:GetSetting(key)
    return db.profile.settings[key]
end

function Storage:SetSetting(key, value)
    db.profile.settings[key] = value
end
