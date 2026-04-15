local addonName, addon = ...
addon.EncounterEngine = {}
local EncounterEngine = addon.EncounterEngine

-- COMBAT_LOG sourceFlags: 반응 적대 비트
local HOSTILE_FLAG = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040

EncounterEngine.activeEncounterID  = nil
EncounterEngine.activeBossData     = nil
EncounterEngine.activeSpecData     = nil
EncounterEngine.encounterStartTime = nil
EncounterEngine.pendingTimers      = {}
EncounterEngine.recentAlerts       = {}  -- hybrid 디듀프: spellID → timestamp

function EncounterEngine:OnEncounterStart(encounterID, encounterName)
    self:Cancel()

    if not addon.SpecMatcher:IsHealer() then
        addon.dprint("힐러 스펙 아님, 인카운터 무시:", encounterID)
        return
    end

    local bossData, dungeonKey = addon.Storage:GetEncounterData(encounterID)
    if not bossData then
        addon.dprint("encounterIndex 매칭 없음:", encounterID)
        return
    end

    local activeSpec = addon.SpecMatcher:GetActiveSpec()
    local specData   = bossData.specs and bossData.specs[activeSpec]
    if not specData then
        addon.dprint("스펙 데이터 없음:", activeSpec, "/ encounter:", encounterID)
        return
    end

    self.activeEncounterID  = encounterID
    self.activeBossData     = bossData
    self.activeSpecData     = specData
    self.encounterStartTime = GetTime()

    local alertMode = addon.Storage:GetSetting("alertMode")
    addon.dprint("ENCOUNTER_START", encounterName, "모드:", alertMode, "스펙:", activeSpec)

    if alertMode == "absolute" or alertMode == "hybrid" then
        self:ScheduleTimeline(specData.timeline)
    end
end

function EncounterEngine:OnEncounterEnd()
    self:Cancel()
end

function EncounterEngine:Cancel()
    for _, t in ipairs(self.pendingTimers) do
        if t.Cancel then t:Cancel() end
    end
    self.pendingTimers      = {}
    self.recentAlerts       = {}
    self.activeEncounterID  = nil
    self.activeBossData     = nil
    self.activeSpecData     = nil
    self.encounterStartTime = nil
end

function EncounterEngine:ScheduleTimeline(timeline)
    if not timeline then return end
    local now       = GetTime()
    local startTime = self.encounterStartTime or now

    for _, entry in ipairs(timeline) do
        local delay = entry.offset - (now - startTime)
        if delay > 0 then
            local spellID = entry.spellID
            local t = C_Timer.NewTimer(delay, function()
                self:TriggerAlert(spellID, "absolute")
            end)
            table.insert(self.pendingTimers, t)
        end
    end
end

function EncounterEngine:OnCombatLog(
    timestamp, subevent, hideCaster,
    sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
    destGUID, destName, destFlags, destRaidFlags, ...)

    if not self.activeSpecData then return end
    if subevent ~= "SPELL_CAST_START" and subevent ~= "SPELL_CAST_SUCCESS" then return end
    if bit.band(sourceFlags, HOSTILE_FLAG) == 0 then return end

    local bossSpellID = ...
    local reactions   = self.activeSpecData.reactions
    if not reactions or not reactions[bossSpellID] then return end

    local alertMode = addon.Storage:GetSetting("alertMode")
    if alertMode == "absolute" then return end  -- absolute 모드는 반응 알림 없음

    for _, entry in ipairs(reactions[bossSpellID]) do
        local playerSpellID = entry.spellID
        local delay         = entry.delay or 0
        local t = C_Timer.NewTimer(delay, function()
            self:TriggerAlert(playerSpellID, "reactive")
        end)
        table.insert(self.pendingTimers, t)
    end
end

function EncounterEngine:TriggerAlert(spellID, source)
    local alertMode = addon.Storage:GetSetting("alertMode")

    -- hybrid 모드: 1.5초 내 동일 spellID 디듀프
    if alertMode == "hybrid" then
        local now  = GetTime()
        local last = self.recentAlerts[spellID]
        if last and (now - last) < 1.5 then
            addon.dprint("hybrid 디듀프:", spellID)
            return
        end
        self.recentAlerts[spellID] = now
    end

    addon.dprint("알림 표시:", spellID, "(" .. source .. ")")
    addon.AlertFrame:ShowAlert(spellID)

    if addon.Storage:GetSetting("soundEnabled") then
        PlaySound(888)
    end
end

function EncounterEngine:OnZoneChanged()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "none" or instanceType == "pvp" or instanceType == "arena" then return end

    local dungeons = addon.Storage:GetDungeons()
    local count    = 0
    local firstName

    for _, dungeon in pairs(dungeons) do
        if dungeon.enabled then
            count = count + 1
            if not firstName then firstName = dungeon.displayName end
        end
    end

    if count > 0 then
        local label = count == 1 and firstName or (firstName .. " 외 " .. (count - 1) .. "개")
        print(string.format("|cff00ff00HealGuide|r: %s 가이드 활성 (%d개 던전)", label, count))
    end
end

function EncounterEngine:TestEncounter(encounterID)
    local bossData, _ = addon.Storage:GetEncounterData(encounterID)
    if not bossData then
        print("|cff00ff00HealGuide|r 등록된 데이터 없음 (encounterID=" .. encounterID .. ")")
        return
    end

    local activeSpec = addon.SpecMatcher:GetActiveSpec()
    if not activeSpec then
        print("|cff00ff00HealGuide|r 힐러 스펙이 아닙니다.")
        return
    end

    local specData = bossData.specs and bossData.specs[activeSpec]
    if not specData then
        print("|cff00ff00HealGuide|r 스펙 데이터 없음: " .. activeSpec)
        return
    end

    local timeline  = specData.timeline  or {}
    local reactions = specData.reactions or {}

    print(string.format("|cff00ff00HealGuide|r 테스트 시작: encounter=%d spec=%s timeline=%d",
        encounterID, activeSpec, #timeline))

    -- timeline 항목을 2초 간격으로 연속 표시
    for i, entry in ipairs(timeline) do
        local spellID = entry.spellID
        C_Timer.After(i * 2.0, function()
            self:TriggerAlert(spellID, "test")
        end)
    end

    -- reactions 에서 최대 3개 샘플
    local rCount = 0
    local base   = #timeline * 2.0
    for _, entries in pairs(reactions) do
        if rCount >= 3 then break end
        for _, entry in ipairs(entries) do
            rCount = rCount + 1
            local spellID = entry.spellID
            C_Timer.After(base + rCount * 2.0, function()
                self:TriggerAlert(spellID, "test-reaction")
            end)
        end
        if rCount >= 3 then break end
    end

    if #timeline == 0 and rCount == 0 then
        print("|cff00ff00HealGuide|r 표시할 알림 항목이 없습니다.")
    end
end
