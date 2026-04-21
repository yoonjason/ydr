local addonName, addon = ...
addon.EncounterTimelineBridge = {}
local Bridge = addon.EncounterTimelineBridge

-- Blizzard 12.0 (Midnight) 네이티브 타임라인 API 통합.
-- C_EncounterTimeline 존재 여부 체크 후 이벤트 구독. 지원 보스에서는
-- 사전 예측 기반으로 플레이어 쿨기를 앞당겨 알림 가능.
--
-- 미지원 보스는 자동으로 기존 OnCombatLog (SPELL_CAST_SUCCESS) 경로로 폴백.

local frame = nil

-- 한 encounter 내에서 같은 bossSpellID 에 대해 중복 스케줄 방지
-- (native 로 예약한 뒤 SPELL_CAST_SUCCESS 가 와도 한 번 더 걸리지 않게)
Bridge.scheduledBossSpells = {}

local function hasAPI()
    return C_EncounterTimeline ~= nil
end

function Bridge:Init()
    if not hasAPI() then
        print("|cffaaaaaa[HG]|r C_EncounterTimeline API 없음 — 네이티브 타임라인 비활성")
        return
    end

    frame = CreateFrame("Frame")
    frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
            Bridge:OnEventAdded(...)
        end
    end)

    print("|cff88ff88[HG]|r 네이티브 타임라인 활성")
end

function Bridge:Reset()
    self.scheduledBossSpells = {}
end

-- Blizzard eventInfo = { id, source, duration, spellID, spellName, iconFileID, color, maxQueueDuration }
function Bridge:OnEventAdded(eventInfo)
    if not eventInfo then return end

    -- source: 0=Encounter, 1=Script, 2=EditMode. 보스 이벤트만 처리.
    if eventInfo.source ~= 0 then return end

    local bossSpellID = eventInfo.spellID
    local duration    = eventInfo.duration
    if not bossSpellID or not duration or duration <= 0 then return end

    -- 활성 인카운터 데이터 확인
    local engine = addon.EncounterEngine
    if not engine or not engine.activeSpecData then return end

    -- EncounterEngine:OnCombatLog 와 동일한 rankerPolicy 분기
    local policy     = addon.Storage:GetSetting("rankerPolicy") or "merge"
    local activeSpec = addon.SpecMatcher and addon.SpecMatcher:GetActiveSpec()
    local reactions = nil

    if policy ~= "off" and addon.RankerDataLoader and activeSpec then
        reactions = addon.RankerDataLoader:LookupBossReactions(activeSpec, engine.activeEncounterID, bossSpellID)
    end
    if not reactions and policy ~= "exclusive" then
        reactions = addon._safeIndex(engine.activeSpecData.reactions or {}, bossSpellID)
    end

    -- 2단 fallback: eventInfo.spellName 으로 _bossNames 역조회
    if not reactions and policy ~= "off" and addon.RankerDataLoader and activeSpec then
        local spellName = eventInfo.spellName
        if type(spellName) == "string" and spellName ~= "" then
            reactions = addon.RankerDataLoader:LookupByBossSpellName(activeSpec, engine.activeEncounterID, spellName)
            if reactions then
                addon.dprint(string.format("[HG-NT] 2단 이름매칭: spellID=%d name=%s", bossSpellID, spellName))
            end
        end
    end

    -- leadIns 는 랭커 데이터 포맷에 없으므로 항상 로컬 activeSpecData 에서만 조회
    local leadInEntries = addon._safeIndex(engine.activeSpecData.leadIns or {}, bossSpellID)

    -- 3단 fallback: reactions 도 leadIns 도 없으면 인카운터 빈도 기반 즉시 추천
    if not reactions and not leadInEntries then
        if policy ~= "off" and addon.RankerDataLoader and activeSpec then
            local candidates = addon.RankerDataLoader:LookupEncounterFallbackReaction(activeSpec, engine.activeEncounterID)
            if candidates then
                local now = GetTime()
                for _, candidate in ipairs(candidates) do
                    local sid = candidate.spellID
                    local onCD = false
                    local cdStart, cdDur = GetSpellCooldown(sid)
                    if cdStart and cdDur and cdStart > 0 and cdDur > 1.5 and (cdStart + cdDur - now) > 0 then
                        onCD = true
                    end
                    if not onCD then
                        engine.recentFallbackAlerts = engine.recentFallbackAlerts or {}
                        if not engine.recentFallbackAlerts[sid] or (now - engine.recentFallbackAlerts[sid]) >= 10 then
                            engine.recentFallbackAlerts[sid] = now
                            local leadTime = addon.Storage:GetSetting("leadTime") or 0
                            local schedule = math.max(0, duration - leadTime)
                            addon.dprint(string.format("[HG-NT] 3단 fallback: spellID=%d score=%.1f delay=%.1f", bossSpellID, candidate.score, schedule))
                            engine:_scheduleAlert(sid, schedule, "fallback", nil, function()
                                if engine.paused then return end
                                engine:TriggerAlert(sid, "fallback")
                            end)
                            self.scheduledBossSpells[bossSpellID] = GetTime()
                        end
                        break
                    end
                end
            end
        end
        addon.dprint(string.format("[HG-NT] native event spellID=%d duration=%.1f (매핑 없음)",
            bossSpellID, duration))
        return
    end

    -- 중복 방지: 같은 bossSpellID 는 최근 0.2초 내 재스케줄 금지
    local now = GetTime()
    local lastSchedule = self.scheduledBossSpells[bossSpellID]
    if lastSchedule and (now - lastSchedule) < 0.2 then return end
    self.scheduledBossSpells[bossSpellID] = now

    local leadTime = addon.Storage:GetSetting("leadTime") or 0
    local scheduledCount = 0

    -- leadIns: 보스 캐스트 이전 램프 시퀀스 (offset 음수)
    -- 예: duration=10, offset=-8 → 10 + (-8) - leadTime = 2 - leadTime 뒤에 예약
    if leadInEntries then
        for _, entry in ipairs(leadInEntries) do
            local playerSpellID  = entry.spellID
            local leadOffset     = entry.offset or 0  -- 음수
            local schedule       = duration + leadOffset - leadTime
            local entryCondition = entry.condition
            if schedule > -0.5 then
                engine:_scheduleAlert(playerSpellID, math.max(0, schedule), "leadIn", nil, function()
                    if addon.ConditionEvaluator:ShouldFire(entryCondition) then
                        engine:TriggerAlert(playerSpellID, "leadIn")
                    else
                        engine:_statInc("conditionSkipped")
                    end
                end)
                scheduledCount = scheduledCount + 1
            end
            -- schedule < -0.5: 너무 늦음, 스킵
        end
    end

    -- reactions: 보스 캐스트 이후 반응 시퀀스
    if reactions then
        for _, entry in ipairs(reactions) do
            local playerSpellID  = entry.spellID
            local reactionDelay  = entry.delay or 0
            local schedule       = duration + reactionDelay - leadTime
            local entryCondition = entry.condition
            engine:_scheduleAlert(playerSpellID, math.max(0, schedule), "native", nil, function()
                if addon.ConditionEvaluator:ShouldFire(entryCondition) then
                    engine:TriggerAlert(playerSpellID, "native")
                else
                    engine:_statInc("conditionSkipped")
                end
            end)
            scheduledCount = scheduledCount + 1
        end
    end

    print(string.format("|cff88ff88[HG-NT]|r boss spellID=%d duration=%.1f → %d개 알림 예약 (lead=%.1f, leadIns=%s reactions=%s)",
        bossSpellID, duration, scheduledCount, leadTime,
        leadInEntries and "Y" or "N", reactions and "Y" or "N"))
end
