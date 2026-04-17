local addonName, addon = ...
addon.EncounterEngine = {}
local EncounterEngine = addon.EncounterEngine

-- N1: fallback 제거 — TWW에서 COMBATLOG_OBJECT_REACTION_HOSTILE 는 항상 정의됨
local HOSTILE_FLAG = COMBATLOG_OBJECT_REACTION_HOSTILE

EncounterEngine.activeEncounterID  = nil
EncounterEngine.activeBossData     = nil
EncounterEngine.activeSpecData     = nil
EncounterEngine.encounterStartTime = nil
EncounterEngine.cachedAlertMode    = nil   -- N2: OnEncounterStart 시 1회 캐싱
EncounterEngine.bossUnitID         = nil   -- 보스 유닛 ID (boss1~boss5)
EncounterEngine.currentPhase       = 1     -- ENCOUNTER_PHASE_UPDATE 추적
EncounterEngine.pendingTimers      = {}
EncounterEngine.recentAlerts       = {}    -- hybrid 디듀프: spellID → timestamp
EncounterEngine.playerCooldowns    = {}    -- 쿨다운 추적: spellID → GetTime()
EncounterEngine.stats              = { fired = 0, conditionSkipped = 0, cooldownSkipped = 0, used = 0, keystoneSkipped = 0 }
EncounterEngine.recentTrashAlerts  = {}    -- 트래시 디듀프: spellID → timestamp
EncounterEngine.combatLog          = {}    -- 전투 기록: { type, spellID, timestamp }
EncounterEngine.scheduledAlerts    = {}    -- 타이머 바용: { spellID, fireTime, source }
EncounterEngine.paused             = false
EncounterEngine.keystoneLevel      = 0
EncounterEngine.activeDungeonKey   = ""
EncounterEngine.activeAffixIDs    = {}

function EncounterEngine:OnEncounterStart(encounterID, encounterName)
    self:Cancel()

    if not addon.SpecMatcher:IsHealer() then
        print("|cffff8888[HG]|r 힐러 스펙 아님, 인카운터 무시: " .. tostring(encounterID))
        return
    end

    local bossData, dungeonKey = addon.Storage:GetEncounterData(encounterID)
    if not bossData then
        print(string.format("|cffff8888[HG]|r encounterID 매칭 없음: %d (등록된 던전에 해당 ID 없음)", encounterID))
        -- 등록된 encounterID 목록 출력 (진단용)
        local db = HealGuideCharDB
        if db and db.encounterIndex then
            local ids = {}
            for id in pairs(db.encounterIndex) do table.insert(ids, tostring(id)) end
            table.sort(ids)
            print("|cffaaaaaa[HG]|r 등록된 encounterID: " .. (#ids > 0 and table.concat(ids, ", ") or "(없음)"))
        end
        return
    end

    local activeSpec = addon.SpecMatcher:GetActiveSpec()
    local specData   = bossData.specs and bossData.specs[activeSpec]
    if not specData then
        print(string.format("|cffff8888[HG]|r 스펙 데이터 없음: 활성=%s, 등록된 키: %s",
            tostring(activeSpec),
            (function()
                local keys = {}
                if bossData.specs then
                    for k in pairs(bossData.specs) do table.insert(keys, k) end
                end
                return #keys > 0 and table.concat(keys, ",") or "(없음)"
            end)()
        ))
        return
    end

    print(string.format("|cff88ff88[HG]|r 매칭 성공: encounter=%d spec=%s timeline=%d reactions=%d",
        encounterID, activeSpec, #(specData.timeline or {}),
        (function() local n = 0; for _ in pairs(specData.reactions or {}) do n = n + 1 end; return n end)()
    ))

    self.activeEncounterID  = encounterID
    self.activeBossData     = bossData
    self.activeSpecData     = specData
    self.encounterStartTime = GetTime()
    self.cachedAlertMode    = addon.Storage:GetSetting("alertMode")  -- N2

    self.currentPhase = 1
    self.bossUnitID = self:_FindBossUnit()

    addon.dprint("ENCOUNTER_START", encounterName, "모드:", self.cachedAlertMode, "스펙:", activeSpec, "보스유닛:", self.bossUnitID or "없음")

    if self.cachedAlertMode == "absolute" or self.cachedAlertMode == "hybrid" then
        self:ScheduleTimeline(specData.timeline)
    end
end

function EncounterEngine:OnEncounterEnd()
    local s = self.stats
    if s.fired > 0 or s.conditionSkipped > 0 or s.cooldownSkipped > 0 or s.keystoneSkipped > 0 then
        print(string.format(
            "|cff88ff88[HG]|r 전투 요약: 알림 %d개 | 조건 스킵 %d | 쿨다운 스킵 %d | 키스톤 스킵 %d | 실제 사용 %d",
            s.fired, s.conditionSkipped, s.cooldownSkipped, s.keystoneSkipped, s.used
        ))
    end

    if #self.combatLog > 0 and self.activeEncounterID then
        self:_SaveCombatRecord()
    end

    self:Cancel()
    self.stats = { fired = 0, conditionSkipped = 0, cooldownSkipped = 0, used = 0, keystoneSkipped = 0 }
end

function EncounterEngine:OnChallengeModeStart(mapID)
    local ksLevel, affixes = C_ChallengeMode.GetActiveKeystoneInfo()
    self.keystoneLevel  = ksLevel or 0
    self.activeAffixIDs = affixes or {}

    local keyMap = addon.DungeonMappings and addon.DungeonMappings.keyByMapID
    if keyMap and mapID then
        self.activeDungeonKey = keyMap[mapID] or ""
        if self.activeDungeonKey == "" then
            addon.dprint("확인 필요: mapID=" .. tostring(mapID) .. " → dungeonKey 매핑 없음")
        end
    else
        addon.dprint("확인 필요: DungeonMappings.keyByMapID 미존재 (mapID=" .. tostring(mapID) .. ")")
    end

    addon.dprint("CHALLENGE_MODE_START keystoneLevel=" .. self.keystoneLevel
        .. " dungeonKey=" .. self.activeDungeonKey
        .. " affixes=" .. #self.activeAffixIDs)
end

function EncounterEngine:OnChallengeModeCompleted()
    self.keystoneLevel    = 0
    self.activeDungeonKey = ""
    self.activeAffixIDs   = {}
    self.recentTrashAlerts = {}
end

function EncounterEngine:_SaveCombatRecord()
    local db = HealGuideCharDB
    if not db then return end
    db.combatHistory = db.combatHistory or {}

    local record = {
        encounterID = self.activeEncounterID,
        timestamp   = time(),
        duration    = GetTime() - (self.encounterStartTime or GetTime()),
        stats       = {
            fired            = self.stats.fired,
            conditionSkipped = self.stats.conditionSkipped,
            cooldownSkipped  = self.stats.cooldownSkipped,
            keystoneSkipped  = self.stats.keystoneSkipped,
            used             = self.stats.used,
        },
        events = self.combatLog,
    }

    table.insert(db.combatHistory, record)

    -- 최근 50개만 유지
    while #db.combatHistory > 50 do
        table.remove(db.combatHistory, 1)
    end
end

function EncounterEngine:Cancel()
    for _, t in ipairs(self.pendingTimers) do
        if t and t.Cancel then t:Cancel() end
    end
    self.pendingTimers      = {}
    self.recentAlerts       = {}
    self.recentTrashAlerts  = {}
    self.playerCooldowns    = {}
    self.combatLog          = {}
    self.scheduledAlerts    = {}
    self.paused             = false
    self.activeEncounterID  = nil
    self.activeBossData     = nil
    self.activeSpecData     = nil
    self.encounterStartTime = nil
    self.cachedAlertMode    = nil
    self.bossUnitID         = nil
    self.currentPhase       = 1
    if addon.EncounterTimelineBridge then
        addon.EncounterTimelineBridge:Reset()
    end
end

function EncounterEngine:ScheduleTimeline(timeline)
    if not timeline then return end
    local now       = GetTime()
    local startTime = self.encounterStartTime or now
    local leadTime  = addon.Storage:GetSetting("leadTime") or 0
    local scheduled = 0

    for _, entry in ipairs(timeline) do
        -- §5D: M+ 활성(keystoneLevel > 0) 일 때만 minKeystone 필터 적용
        if not (self.keystoneLevel > 0 and entry.minKeystone and self.keystoneLevel < entry.minKeystone) then
        local delay = entry.offset - (now - startTime) - leadTime
        if delay > 0 then
            local spellID        = entry.spellID
            local entryCondition = entry.condition
            local fireTime = GetTime() + delay
            local alertInfo = { spellID = spellID, fireTime = fireTime, source = "absolute" }
            table.insert(self.scheduledAlerts, alertInfo)
            local t = C_Timer.NewTimer(delay, function()
                self:_RemoveScheduledAlert(alertInfo)
                if self.paused then return end
                if addon.ConditionEvaluator:ShouldFire(entryCondition) then
                    self:TriggerAlert(spellID, "absolute")
                else
                    self.stats.conditionSkipped = self.stats.conditionSkipped + 1
                end
            end)
            table.insert(self.pendingTimers, t)
            scheduled = scheduled + 1
        end
        end  -- minKeystone 필터
    end
    print(string.format("|cff88ff88[HG]|r absolute 타이머 %d개 예약 (lead=%.1fs)", scheduled, leadTime))
end

function EncounterEngine:OnCombatLog(
    timestamp, subevent, hideCaster,
    sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
    destGUID, destName, destFlags, destRaidFlags, ...)

    if not self.activeSpecData then return end
    if subevent ~= "SPELL_CAST_START" and subevent ~= "SPELL_CAST_SUCCESS" then return end
    if bit.band(sourceFlags, HOSTILE_FLAG) == 0 then return end

    -- N2: 캐시된 alertMode 사용 (핫 패스 Storage 접근 회피)
    if self.cachedAlertMode == "absolute" then return end

    local bossSpellID = ...
    local reactions   = self.activeSpecData.reactions

    -- U2.5: 네이티브 타임라인이 이미 이 bossSpellID 를 예약했다면 COMBAT_LOG 경로 스킵.
    -- Bridge.scheduledBossSpells[id] 에 타임스탬프가 있으면 ENCOUNTER_TIMELINE_EVENT_ADDED
    -- 가 먼저 도착해서 leadIns/reactions 를 이미 걸었다는 뜻. 여기서 또 거는 건 중복.
    -- 윈도우 30s: 같은 보스가 같은 스킬을 반복 시전할 때 네이티브가 매번 ADDED 를 다시
    -- 쏘며 타임스탬프를 갱신하므로 윈도우 안에 항상 들어옴.
    local bridge = addon.EncounterTimelineBridge
    if bridge and bossSpellID then
        local lastNative = bridge.scheduledBossSpells and bridge.scheduledBossSpells[bossSpellID]
        if lastNative and (GetTime() - lastNative) < 30 then
            addon.dprint(string.format("[HG-CL] boss cast spellID=%s → 네이티브 예약 존재, 스킵",
                tostring(bossSpellID)))
            return
        end
    end

    addon.dprint(string.format("[HG-CL] boss cast: name=%s spellID=%s matched=%s",
        tostring(sourceName), tostring(bossSpellID),
        (reactions and reactions[bossSpellID]) and "YES" or "NO"))
    if not reactions or not reactions[bossSpellID] then return end

    local leadTime = addon.Storage:GetSetting("leadTime") or 0
    for _, entry in ipairs(reactions[bossSpellID]) do
        -- §5D: M+ 활성일 때만 minKeystone 필터 적용
        if not (self.keystoneLevel > 0 and entry.minKeystone and self.keystoneLevel < entry.minKeystone) then
        local playerSpellID  = entry.spellID
        local delay          = math.max(0, (entry.delay or 0) - leadTime)
        local entryCondition = entry.condition
        local fireTime = GetTime() + delay
        local alertInfo = { spellID = playerSpellID, fireTime = fireTime, source = "reactive" }
        table.insert(self.scheduledAlerts, alertInfo)
        local t = C_Timer.NewTimer(delay, function()
            self:_RemoveScheduledAlert(alertInfo)
            if self.paused then return end
            if addon.ConditionEvaluator:ShouldFire(entryCondition) then
                self:TriggerAlert(playerSpellID, "reactive")
            else
                self.stats.conditionSkipped = self.stats.conditionSkipped + 1
            end
        end)
        table.insert(self.pendingTimers, t)
        end  -- minKeystone 필터
    end
end

function EncounterEngine:TriggerAlert(spellID, source)
    -- §5B 전역 게이트: M+ 활성 중 keystoneMinLevel 미달이면 스킵
    if self.keystoneLevel > 0 then
        local minLvl = addon.Storage:GetSetting("keystoneMinLevel") or 2
        if self.keystoneLevel < minLvl then
            self.stats.keystoneSkipped = self.stats.keystoneSkipped + 1
            return
        end
    end

    local alertMode = self.cachedAlertMode or addon.Storage:GetSetting("alertMode")

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

    -- 쿨다운 추적: 플레이어가 최근 이 스킬을 사용했으면 재알림 스킵
    local lastUsed = self.playerCooldowns[spellID]
    if lastUsed then
        local start, duration, enable = GetSpellCooldown(spellID)
        if start and start > 0 and duration and duration > 1.5 and enable == 1 then
            addon.dprint("쿨다운 스킵:", spellID, "잔여:", string.format("%.1f", start + duration - GetTime()))
            self.stats.cooldownSkipped = self.stats.cooldownSkipped + 1
            return
        end
    end

    self.stats.fired = self.stats.fired + 1
    addon.dprint("알림 표시:", spellID, "(" .. source .. ")")
    addon.AlertFrame:ShowAlert(spellID)

    table.insert(self.combatLog, {
        type = "alert",
        spellID = spellID,
        source = source,
        timestamp = GetTime() - (self.encounterStartTime or GetTime()),
    })
end

function EncounterEngine:OnPlayerCast(spellID)
    if not self.activeEncounterID then return end
    self.playerCooldowns[spellID] = GetTime()
    self.stats.used = self.stats.used + 1

    table.insert(self.combatLog, {
        type = "used",
        spellID = spellID,
        timestamp = GetTime() - (self.encounterStartTime or GetTime()),
    })
end

function EncounterEngine:_FindBossUnit()
    for i = 1, 5 do
        local unit = "boss" .. i
        if UnitExists(unit) and not UnitIsDead(unit) then
            return unit
        end
    end
    return nil
end

function EncounterEngine:GetBossHP()
    local unit = self.bossUnitID
    if not unit or not UnitExists(unit) then
        unit = self:_FindBossUnit()
        self.bossUnitID = unit
    end
    if not unit then return nil end
    local maxHP = UnitHealthMax(unit)
    if not maxHP or maxHP <= 0 then return nil end
    return UnitHealth(unit) / maxHP
end

function EncounterEngine:OnPhaseUpdate(phase)
    if phase and phase > 0 then
        self.currentPhase = phase
        addon.dprint("페이즈 변경:", phase)
    end
end

function EncounterEngine:_RemoveScheduledAlert(alertInfo)
    for i = #self.scheduledAlerts, 1, -1 do
        if self.scheduledAlerts[i] == alertInfo then
            table.remove(self.scheduledAlerts, i)
            break
        end
    end
end

function EncounterEngine:GetUpcomingAlerts(limit)
    local now = GetTime()
    local upcoming = {}
    local seen = {}
    for _, info in ipairs(self.scheduledAlerts) do
        local remaining = info.fireTime - now
        if remaining > 0 then
            if not seen[info.spellID] or seen[info.spellID] > remaining then
                seen[info.spellID] = remaining
            end
        end
    end
    for spellID, remaining in pairs(seen) do
        table.insert(upcoming, { spellID = spellID, remaining = remaining })
    end
    table.sort(upcoming, function(a, b) return a.remaining < b.remaining end)
    if limit and #upcoming > limit then
        local trimmed = {}
        for i = 1, limit do trimmed[i] = upcoming[i] end
        return trimmed
    end
    return upcoming
end

function EncounterEngine:Pause()
    self.paused = true
    print("|cff00ff00HealGuide|r 알림 일시 중지")
end

function EncounterEngine:Resume()
    self.paused = false
    print("|cff00ff00HealGuide|r 알림 재개")
end

function EncounterEngine:OnUnitSpellcast(unit, spellID, event)
    if not addon.SpecMatcher:IsHealer() then return end
    -- 트래시 알림은 5인 던전 전용 (일반/영웅/M+). 레이드/야외 제외.
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "party" then return end
    if not unit or string.sub(unit, 1, 9) ~= "nameplate" then return end

    local whitelist = addon.TrashWhitelist
    if not whitelist or not whitelist[spellID] then return end

    -- §5B 키스톤 레벨 게이트 — M+ 진행 중일 때만 적용
    if self.keystoneLevel > 0 then
        local minLvl = addon.Storage:GetSetting("keystoneMinLevel") or 2
        if self.keystoneLevel < minLvl then return end
    end

    -- 0.5초 디듀프 (같은 nameplateN → nameplateMn 중복 이벤트 방지)
    local now = GetTime()
    if self.recentTrashAlerts[spellID] and (now - self.recentTrashAlerts[spellID]) < 0.5 then return end
    self.recentTrashAlerts[spellID] = now

    local entry = whitelist[spellID]
    addon.dprint("[HG-Trash]", event, "unit=" .. unit, "bossSpellID=" .. tostring(spellID), "→ response=" .. tostring(entry.responseSpellID))
    addon.AlertFrame:ShowAlert(entry.responseSpellID)
end

function EncounterEngine:OnZoneChanged()
    -- S4: 전투 중(인카운터 활성)이면 zone 토스트 skip
    if self.activeEncounterID then return end

    local _, instanceType = GetInstanceInfo()
    if instanceType == "none" then
        self.keystoneLevel    = 0
        self.activeDungeonKey = ""
        self.activeAffixIDs   = {}
        return
    end
    if instanceType == "pvp" or instanceType == "arena" then return end

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

    -- B2: C_Timer.NewTimer 로 교체, pendingTimers 에 등록 → 스펙 스왑 시 취소 가능
    for i, entry in ipairs(timeline) do
        local spellID = entry.spellID
        local t = C_Timer.NewTimer(i * 2.0, function()
            self:TriggerAlert(spellID, "test")
        end)
        table.insert(self.pendingTimers, t)
    end

    local rCount = 0
    local base   = #timeline * 2.0
    for _, entries in pairs(reactions) do
        if rCount >= 3 then break end
        for _, entry in ipairs(entries) do
            rCount = rCount + 1
            local spellID = entry.spellID
            local t = C_Timer.NewTimer(base + rCount * 2.0, function()
                self:TriggerAlert(spellID, "test-reaction")
            end)
            table.insert(self.pendingTimers, t)
        end
        if rCount >= 3 then break end
    end

    if #timeline == 0 and rCount == 0 then
        print("|cff00ff00HealGuide|r 표시할 알림 항목이 없습니다.")
    end
end
