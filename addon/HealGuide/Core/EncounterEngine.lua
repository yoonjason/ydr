local addonName, addon = ...
addon.EncounterEngine = {}
local EncounterEngine = addon.EncounterEngine

-- N1: fallback 제거 — TWW에서 COMBATLOG_OBJECT_REACTION_HOSTILE 는 항상 정의됨
local HOSTILE_FLAG = COMBATLOG_OBJECT_REACTION_HOSTILE

local function statsNew()
    return { fired = 0, conditionSkipped = 0, cooldownSkipped = 0, used = 0, keystoneSkipped = 0 }
end

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
EncounterEngine.stats              = statsNew()
EncounterEngine.recentTrashAlerts  = {}    -- 트래시 디듀프: spellID → timestamp
EncounterEngine.combatLog          = {}    -- 전투 기록: { type, spellID, timestamp }
EncounterEngine.scheduledAlerts    = {}    -- TimelineFrame 표시 + 취소(캐스트 stop) 용: { spellID, fireTime, source, [castKey], [timer] }
EncounterEngine.paused             = false
EncounterEngine.keystoneLevel      = 0
EncounterEngine.activeDungeonKey   = ""
EncounterEngine.activeAffixIDs    = {}
EncounterEngine.spellMetaCache     = {}    -- [spellID] = { baseCD, castTime }

local function getSpellMeta(spellID)
    local cache = EncounterEngine.spellMetaCache
    local meta = cache[spellID]
    if not meta then
        local baseCD = 0
        local ok1, cd = pcall(GetSpellBaseCooldown, spellID)
        if ok1 and type(cd) == "number" then baseCD = cd end
        local castTime = 0
        if C_Spell and C_Spell.GetSpellInfo then
            local ok2, info = pcall(C_Spell.GetSpellInfo, spellID)
            if ok2 and info and type(info.castTime) == "number" then castTime = info.castTime end
        end
        meta = { baseCD = baseCD, castTime = castTime }
        cache[spellID] = meta
    end
    return meta
end

-- 11.0+ secret spellID 방어: pcall 로 테이블 인덱스 시도. 실패/nil 이면 nil 반환.
local function safeIndex(tbl, key)
    if not tbl or type(key) ~= "number" then return nil end
    local ok, val = pcall(function() return tbl[key] end)
    return ok and val or nil
end
addon._safeIndex = safeIndex

function EncounterEngine:_statInc(key)
    self.stats[key] = (self.stats[key] or 0) + 1
end

function EncounterEngine:_statsReset()
    self.stats = statsNew()
end

function EncounterEngine:OnEncounterStart(encounterID, encounterName)
    self:Cancel()

    if not addon.SpecMatcher:IsHealer() then
        print("|cffff8888[HG]|r 힐러 스펙 아님, 인카운터 무시: " .. tostring(encounterID))
        return
    end

    local activeSpec = addon.SpecMatcher:GetActiveSpec()
    local bossData, dungeonKey = addon.Storage:GetEncounterData(encounterID)
    if not bossData then
        local policy = addon.Storage:GetSetting("rankerPolicy") or "merge"
        if policy ~= "off" and addon.RankerDataLoader and addon.RankerDataLoader:HasEncounterData(activeSpec, encounterID) then
            self.activeEncounterID  = encounterID
            self.activeBossData     = nil
            self.activeSpecData     = { reactions = {}, timeline = {}, leadIns = {} }
            self.encounterStartTime = GetTime()
            self.cachedAlertMode    = addon.Storage:GetSetting("alertMode")
            self.currentPhase = 1
            self.bossUnitID = self:_FindBossUnit()
            local entryCount = addon.RankerDataLoader:CountEntries(activeSpec, encounterID)
            print(string.format("|cff88ff88[HG]|r 랭커 전용 모드: encounter=%d spec=%s 랭커매핑=%d개", encounterID, activeSpec, entryCount))
            return
        end
        print(string.format("|cffff8888[HG]|r HGPT_Data 와 랭커 데이터 모두에 encounterID %d 없음", encounterID))
        local db = HealGuideCharDB
        if db and db.encounterIndex then
            local ids = {}
            for id in pairs(db.encounterIndex) do table.insert(ids, tostring(id)) end
            table.sort(ids)
            print("|cffaaaaaa[HG]|r 등록된 encounterID: " .. (#ids > 0 and table.concat(ids, ", ") or "(없음)"))
        end
        return
    end

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
    self:_statsReset()
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
        local spellID = entry.spellID
        if type(spellID) == "number" then
            local meta = getSpellMeta(spellID)
            local rawDelay = entry.offset - (now - startTime) - leadTime - (meta.castTime / 1000)
            if rawDelay > 0 then
                local entryCondition = entry.condition
                self:_scheduleAlert(spellID, rawDelay, "absolute", nil, function()
                    if self.paused then return end
                    if addon.ConditionEvaluator:ShouldFire(entryCondition) then
                        self:TriggerAlert(spellID, "absolute")
                    else
                        self:_statInc("conditionSkipped")
                    end
                end)
                scheduled = scheduled + 1
            end
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
    -- 11.0+ secret spellID 가드 — type() 으로는 분별 불가, pcall 로 인덱스 시도.
    if type(bossSpellID) ~= "number" then return end

    -- rankerPolicy 기반 조회
    local policy     = addon.Storage:GetSetting("rankerPolicy") or "merge"
    local activeSpec = addon.SpecMatcher and addon.SpecMatcher:GetActiveSpec()
    local matched    = nil

    if policy ~= "off" and addon.RankerDataLoader and activeSpec then
        matched = addon.RankerDataLoader:LookupBossReactions(activeSpec, self.activeEncounterID, bossSpellID)
    end
    if not matched and policy ~= "exclusive" then
        if self.activeSpecData.reactions and next(self.activeSpecData.reactions) then
            matched = safeIndex(self.activeSpecData.reactions, bossSpellID)
        end
    end
    if not matched then return end

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
        matched and "YES" or "NO"))

    local leadTime = addon.Storage:GetSetting("leadTime") or 0
    -- 베타: 쿨타임 fallback — 추천 스킬이 시전 예정 시점에 쿨이면 알림 스킵.
    -- 카테고리 태깅된 다른 스킬로 자동 대체는 하지 않음 (랭커 데이터에 이미 여러
    -- 순위 후보가 포함돼 있어 각각 별도 알림으로 들어감).
    local useBetaCD = addon.Storage:GetSetting("useBetaCooldownFallback")

    -- 전술 가이드 1줄 선택: matched._tactics 중 우선순위 최상 (critical > important > note).
    -- 같은 bossSpellID 의 모든 힐 알림에 동일한 전술 텍스트 표시.
    local pickedTacticAction, pickedTacticPriority
    if type(matched._tactics) == "table" then
        local priorityRank = { critical = 3, important = 2, note = 1 }
        local bestRank = 0
        for _, t in ipairs(matched._tactics) do
            if type(t) == "table" and type(t.action) == "string" and t.action ~= "" then
                local rank = priorityRank[t.priority] or 0
                if rank > bestRank then
                    bestRank = rank
                    pickedTacticAction = t.action
                    pickedTacticPriority = t.priority
                end
            end
        end
        if pickedTacticAction and pickedTacticPriority then
            -- ASCII 마커만 사용 — WoW 클라이언트 기본 폰트 글리프 호환 (★/☆ 는 tofu 위험)
            local marker = ""
            if pickedTacticPriority == "critical" then marker = "[!] "
            elseif pickedTacticPriority == "important" then marker = "[~] "
            end
            pickedTacticAction = marker .. pickedTacticAction
        end
    end

    for _, entry in ipairs(matched) do
        -- §5D: M+ 활성일 때만 minKeystone 필터 적용
        if not (self.keystoneLevel > 0 and entry.minKeystone and self.keystoneLevel < entry.minKeystone) then
        local playerSpellID = entry.spellID
        if type(playerSpellID) == "number" then
            local meta = getSpellMeta(playerSpellID)
            local rawDelay = (entry.delay or 0) - leadTime - (meta.castTime / 1000)
            local delay = math.max(0, rawDelay)

            -- 베타 쿨타임 체크: 스킬 미보유 또는 예상 시전 시점에 쿨이 안 돌 스킬은 스킵.
            -- BLOCKER-3: GCD (전역 쿨, ~1.5s) 를 실제 쿨로 오인하지 않도록 duration > 1.5 가드.
            -- GCD 는 모든 스킬에 균일 적용되므로 "이 스킬이 쿨" 이라고 판단하면 안 됨.
            local betaSkip = false
            if useBetaCD then
                if IsSpellKnown and not IsSpellKnown(playerSpellID) then
                    betaSkip = true
                    addon.dprint(string.format("[HG-BETA] spellID=%s 미보유 — 스킵",
                        tostring(playerSpellID)))
                else
                    local cdStart, cdDuration = GetSpellCooldown(playerSpellID)
                    if cdStart and cdDuration and cdStart > 0 and cdDuration > 1.5 then
                        local remaining = cdStart + cdDuration - GetTime()
                        if remaining > delay then
                            betaSkip = true
                            addon.dprint(string.format(
                                "[HG-BETA] spellID=%s 쿨 %.1fs 남음 (예상 delay %.1fs) — 스킵",
                                tostring(playerSpellID), remaining, delay))
                        end
                    end
                end
            end

            local entryCondition = entry.condition
            if not betaSkip then
            -- 전술 액션/우선순위를 클로저에 캡처해 예약 시점이 아닌 실제 발사 시점에 전달
            local capturedTacticAction   = pickedTacticAction
            local capturedTacticPriority = pickedTacticPriority
            self:_scheduleAlert(playerSpellID, delay, "reactive", nil, function()
                if self.paused then return end
                if addon.ConditionEvaluator:ShouldFire(entryCondition) then
                    self:TriggerAlert(playerSpellID, "reactive", capturedTacticAction, capturedTacticPriority)
                else
                    self:_statInc("conditionSkipped")
                end
            end)
            end  -- 베타 스킵
        end
        end  -- minKeystone 필터
    end
end

-- TriggerAlert(spellID, source [, tacticAction, tacticPriority])
--   tacticAction / tacticPriority: 해당 힐 스킬을 유발한 보스 스킬의 전술 가이드 1줄 (옵션)
function EncounterEngine:TriggerAlert(spellID, source, tacticAction, tacticPriority)
    -- §5B 전역 게이트: M+ 활성 중 keystoneMinLevel 미달이면 스킵
    if self.keystoneLevel > 0 then
        local minLvl = addon.Storage:GetSetting("keystoneMinLevel") or 2
        if self.keystoneLevel < minLvl then
            self:_statInc("keystoneSkipped")
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
            self:_statInc("cooldownSkipped")
            return
        end
    end

    self:_statInc("fired")
    addon.dprint("알림 표시:", spellID, "(" .. source .. ")")
    addon.AlertFrame:ShowAlert(spellID, tacticAction, tacticPriority)

    table.insert(self.combatLog, {
        type = "alert",
        spellID = spellID,
        source = source,
        timestamp = GetTime() - (self.encounterStartTime or GetTime()),
    })
end

function EncounterEngine:OnPlayerCast(spellID)
    if not self.activeEncounterID then return end
    if type(spellID) ~= "number" then return end
    -- secret spellID 가드: 쓰기 시도가 에러 날 수 있으므로 pcall.
    local ok = pcall(function() self.playerCooldowns[spellID] = GetTime() end)
    if not ok then return end
    self:_statInc("used")

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


function EncounterEngine:_RemoveScheduledAlert(alertInfo)
    for i = #self.scheduledAlerts, 1, -1 do
        if self.scheduledAlerts[i] == alertInfo then
            table.remove(self.scheduledAlerts, i)
            break
        end
    end
end

function EncounterEngine:_scheduleAlert(spellID, delay, source, castKey, onFire)
    -- delay <= 0: 스케줄 없이 즉시 발화. scheduledAlerts/pendingTimers 삽입 생략
    -- (1프레임 수명 좀비 엔트리가 GetUpcomingAlerts 나 TimelineFrame 에 잡히는 것 방지).
    if delay <= 0 then
        onFire()
        return nil
    end
    local alertInfo = {
        spellID  = spellID,
        fireTime = GetTime() + delay,
        source   = source,
    }
    if castKey then alertInfo.castKey = castKey end
    table.insert(self.scheduledAlerts, alertInfo)
    local timer = C_Timer.NewTimer(delay, function()
        self:_RemoveScheduledAlert(alertInfo)
        onFire()
    end)
    alertInfo.timer = timer
    table.insert(self.pendingTimers, timer)
    return alertInfo
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

    -- 11.0+ 일부 주문의 spellID 는 secret 플래그 — type() 은 number 반환하지만
    -- 테이블 인덱스 시 'table index is secret' 런타임 에러. pcall 로 안전 조회.
    local whitelist = addon.TrashWhitelist
    if not whitelist then return end
    local entry = safeIndex(whitelist, spellID)
    if not entry then return end

    -- §5B 키스톤 레벨 게이트 — M+ 진행 중일 때만 적용
    if self.keystoneLevel > 0 then
        local minLvl = addon.Storage:GetSetting("keystoneMinLevel") or 2
        if self.keystoneLevel < minLvl then return end
    end

    -- 0.5초 디듀프 (같은 nameplateN → nameplateMn 중복 이벤트 방지).
    -- 여기까진 pcall 통과 = spellID 가 secret 아님이 보장 → 일반 인덱스 안전.
    local now = GetTime()
    if self.recentTrashAlerts[spellID] and (now - self.recentTrashAlerts[spellID]) < 0.5 then return end
    self.recentTrashAlerts[spellID] = now

    local _, _, _, startMS, endMS = UnitCastingInfo(unit)
    if not endMS or endMS <= 0 then
        addon.dprint("[HG-Trash]", event, "unit=" .. unit, "→ instant fallback")
        addon.AlertFrame:ShowAlert(entry.responseSpellID)
        return
    end
    local fireTime = endMS / 1000
    local delay = fireTime - GetTime()
    if delay <= 0 then
        addon.dprint("[HG-Trash]", event, "unit=" .. unit, "→ delay<=0 fallback")
        addon.AlertFrame:ShowAlert(entry.responseSpellID)
        return
    end
    local castOk, castKey = pcall(function() return unit .. ":" .. spellID end)
    if not castOk then return end
    self:_scheduleAlert(entry.responseSpellID, delay, "trash-cast", castKey, function()
        addon.AlertFrame:ShowAlert(entry.responseSpellID)
    end)
    addon.dprint("[HG-Trash-Cast]", castKey, "→ fire in", string.format("%.1fs", delay))
end

function EncounterEngine:OnUnitSpellcastStop(unit, spellID)
    local ok, castKey = pcall(function() return unit .. ":" .. spellID end)
    if not ok then return end
    for i = #self.scheduledAlerts, 1, -1 do
        local info = self.scheduledAlerts[i]
        if info.castKey == castKey then
            if info.timer and info.timer.Cancel then info.timer:Cancel() end
            for j = #self.pendingTimers, 1, -1 do
                if self.pendingTimers[j] == info.timer then
                    table.remove(self.pendingTimers, j)
                    break
                end
            end
            table.remove(self.scheduledAlerts, i)
            addon.dprint("[HG-Trash-Cast] interrupted:", castKey)
        end
    end
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
        -- 랭커 전용 경로: OnEncounterStart 가 랭커 데이터 기반으로 activeSpecData 를 빈 구조로 활성화
        self:OnEncounterStart(encounterID, "TEST")
        if not self.activeSpecData then
            print("|cff00ff00HealGuide|r 등록된 데이터 없음 (encounterID=" .. encounterID .. ")")
            return
        end
        local activeSpec = addon.SpecMatcher:GetActiveSpec()
        if activeSpec and addon.RankerDataLoader then
            for _, entry in ipairs(addon.RankerDataLoader:GetEntries()) do
                local meta = entry._meta
                if meta and meta.spec == activeSpec then
                    local encData = entry.data and entry.data[encounterID]
                    if encData then
                        for bossSpellID, _ in pairs(encData) do
                            print(string.format("|cff00ff00HealGuide|r 랭커 시뮬: bossSpellID=%d 시전", bossSpellID))
                            self:OnCombatLog(
                                GetTime(), "SPELL_CAST_SUCCESS", false,
                                "Creature-Test", "TEST_BOSS", HOSTILE_FLAG, 0,
                                "", "", 0, 0,
                                bossSpellID, "TEST", 0)
                            break
                        end
                        break
                    end
                end
            end
        end
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

    -- 시뮬레이션에서도 TimelineFrame 이 동작하도록 실제 인카운터 상태를 세팅.
    -- Cancel() 호출(중지 버튼)로 전체 상태가 정리되므로 누수 없음.
    self:Cancel()
    self.activeEncounterID  = encounterID
    self.activeBossData     = bossData
    self.activeSpecData     = specData
    self.encounterStartTime = GetTime()
    self.cachedAlertMode    = addon.Storage:GetSetting("alertMode")

    local timeline  = specData.timeline  or {}
    local reactions = specData.reactions or {}

    print(string.format("|cff00ff00HealGuide|r 테스트 시작: encounter=%d spec=%s timeline=%d",
        encounterID, activeSpec, #timeline))

    for i, entry in ipairs(timeline) do
        self:_scheduleAlert(entry.spellID, i * 2.0, "test", nil, function()
            self:TriggerAlert(entry.spellID, "test")
        end)
    end

    local rCount = 0
    local base   = #timeline * 2.0
    for _, entries in pairs(reactions) do
        if rCount >= 3 then break end
        for _, entry in ipairs(entries) do
            rCount = rCount + 1
            self:_scheduleAlert(entry.spellID, base + rCount * 2.0, "test-reaction", nil, function()
                self:TriggerAlert(entry.spellID, "test-reaction")
            end)
        end
        if rCount >= 3 then break end
    end

    if #timeline == 0 and rCount == 0 then
        print("|cff00ff00HealGuide|r 표시할 알림 항목이 없습니다.")
    end
end

function EncounterEngine:TestRankerEntry(entry)
    if InCombatLockdown() then
        print("|cff00ff00HealGuide|r 전투 중에는 테스트를 실행할 수 없습니다.")
        return
    end

    -- 진행 중인 랭커 테스트 취소
    if self._rankerTestTimers then
        for _, t in ipairs(self._rankerTestTimers) do pcall(function() t:Cancel() end) end
    end
    self._rankerTestTimers = {}

    local meta = entry._meta or {}
    local spec  = meta.spec
    local data  = entry.data or {}

    if not spec then
        print("|cff00ff00HealGuide|r 랭커 테스트: spec 정보 없음")
        return
    end

    -- 모든 encID × bossSpellID 플래트닝
    local items = {}
    for encID, encData in pairs(data) do
        for bossSpellID, _ in pairs(encData) do
            items[#items + 1] = { encID = encID, bossSpellID = bossSpellID }
        end
    end

    if #items == 0 then
        print("|cff00ff00HealGuide|r 랭커 테스트: 보스 스킬 없음")
        return
    end

    -- 엔진 상태 백업 (CancelRankerTest 에서도 접근 가능하도록 인스턴스 필드에 저장)
    self._rankerTestSavedState = {
        encounterID = self.activeEncounterID,
        specData    = self.activeSpecData,
        alertMode   = self.cachedAlertMode,
    }

    -- 알림 발동에 필요한 최소 상태 주입 (activeSpecData nil 가드)
    self.activeSpecData  = self.activeSpecData or { reactions = {}, leadIns = {}, timeline = {} }
    self.cachedAlertMode = addon.Storage:GetSetting("alertMode")

    local timers  = self._rankerTestTimers
    local INTERVAL = 2.5
    local total   = #items
    local matched = 0
    local failed  = 0

    print(string.format("|cff00ff00HealGuide|r 랭커 데이터 테스트 시작: spec=%s (%d개 보스 스킬)",
        spec, total))

    local function scheduleTimer(delay, fn)
        local t = C_Timer.NewTimer(delay, fn)
        timers[#timers + 1] = t
    end

    for i, item in ipairs(items) do
        local encID     = item.encID
        local bossSpell = item.bossSpellID
        scheduleTimer((i - 1) * INTERVAL, function()
            self.activeEncounterID = encID
            local reactions = addon.RankerDataLoader:LookupBossReactions(spec, encID, bossSpell)
            if reactions and #reactions > 0 then
                matched = matched + 1
                for _, r in ipairs(reactions) do
                    self:TriggerAlert(r.spellID, "ranker-test")
                end
            else
                failed = failed + 1
                print(string.format("|cffffff00[HG]|r 매칭 실패: encID=%d bossSpellID=%d", encID, bossSpell))
            end
        end)
    end

    -- 결과 요약 + 상태 복원
    scheduleTimer(total * INTERVAL, function()
        print(string.format("|cff00ff00HealGuide|r 랭커 테스트 완료: %d개 보스 스킬 중 %d개 알림 발동, %d개 매칭 실패",
            total, matched, failed))
        local saved = self._rankerTestSavedState
        if saved then
            self.activeEncounterID     = saved.encounterID
            self.activeSpecData        = saved.specData
            self.cachedAlertMode       = saved.alertMode
            self._rankerTestSavedState = nil
        end
        self._rankerTestTimers = nil
        if self.onRankerTestFinished then self.onRankerTestFinished() end
    end)
end

function EncounterEngine:IsRankerTestRunning()
    return self._rankerTestTimers ~= nil and #self._rankerTestTimers > 0
end

function EncounterEngine:CancelRankerTest()
    if self._rankerTestTimers then
        for _, t in ipairs(self._rankerTestTimers) do
            pcall(function() t:Cancel() end)
        end
    end
    self._rankerTestTimers = nil
    local saved = self._rankerTestSavedState
    if saved then
        self.activeEncounterID     = saved.encounterID
        self.activeSpecData        = saved.specData
        self.cachedAlertMode       = saved.alertMode
        self._rankerTestSavedState = nil
    end
    print("|cff00ff00HealGuide|r 랭커 테스트 중지")
    if self.onRankerTestFinished then self.onRankerTestFinished() end
end
