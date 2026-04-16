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
    frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
            Bridge:OnEventAdded(...)
        end
        -- STATE_CHANGED 는 현재는 참고만 — 취소 로직은 pendingTimers 에서 별도 처리 필요
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

    local reactions = engine.activeSpecData.reactions
    local leadIns   = engine.activeSpecData.leadIns
    local hasReactions = reactions and reactions[bossSpellID]
    local hasLeadIns   = leadIns and leadIns[bossSpellID]

    if not hasReactions and not hasLeadIns then
        print(string.format("|cffaaaaaa[HG-NT]|r native event spellID=%d duration=%.1f (매핑 없음)",
            bossSpellID, duration))
        return
    end

    -- 중복 방지: 같은 bossSpellID 는 최근 1초 내 재스케줄 금지
    local now = GetTime()
    local lastSchedule = self.scheduledBossSpells[bossSpellID]
    if lastSchedule and (now - lastSchedule) < 1.0 then return end
    self.scheduledBossSpells[bossSpellID] = now

    local leadTime = addon.Storage:GetSetting("leadTime") or 0
    local scheduledCount = 0

    -- leadIns: 보스 캐스트 이전 램프 시퀀스 (offset 음수)
    -- 예: duration=10, offset=-8 → 10 + (-8) - leadTime = 2 - leadTime 뒤에 예약
    if hasLeadIns then
        for _, entry in ipairs(leadIns[bossSpellID]) do
            local playerSpellID  = entry.spellID
            local leadOffset     = entry.offset or 0  -- 음수
            local schedule       = duration + leadOffset - leadTime
            local entryCondition = entry.condition
            if schedule > 0 then
                local t = C_Timer.NewTimer(schedule, function()
                    if addon.ConditionEvaluator:ShouldFire(entryCondition) then
                        engine:TriggerAlert(playerSpellID, "leadIn")
                    end
                end)
                table.insert(engine.pendingTimers, t)
                scheduledCount = scheduledCount + 1
            elseif schedule > -0.5 then
                -- 이미 거의 지났으면 즉시 표시 (램프 후반부)
                if addon.ConditionEvaluator:ShouldFire(entryCondition) then
                    engine:TriggerAlert(playerSpellID, "leadIn-immediate")
                end
                scheduledCount = scheduledCount + 1
            end
            -- schedule < -0.5: 너무 늦음, 스킵
        end
    end

    -- reactions: 보스 캐스트 이후 반응 시퀀스
    if hasReactions then
        for _, entry in ipairs(reactions[bossSpellID]) do
            local playerSpellID  = entry.spellID
            local reactionDelay  = entry.delay or 0
            local schedule       = duration + reactionDelay - leadTime
            local entryCondition = entry.condition
            if schedule > 0 then
                local t = C_Timer.NewTimer(schedule, function()
                    if addon.ConditionEvaluator:ShouldFire(entryCondition) then
                        engine:TriggerAlert(playerSpellID, "native")
                    end
                end)
                table.insert(engine.pendingTimers, t)
                scheduledCount = scheduledCount + 1
            else
                if addon.ConditionEvaluator:ShouldFire(entryCondition) then
                    engine:TriggerAlert(playerSpellID, "native-immediate")
                end
                scheduledCount = scheduledCount + 1
            end
        end
    end

    print(string.format("|cff88ff88[HG-NT]|r boss spellID=%d duration=%.1f → %d개 알림 예약 (lead=%.1f, leadIns=%s reactions=%s)",
        bossSpellID, duration, scheduledCount, leadTime,
        hasLeadIns and "Y" or "N", hasReactions and "Y" or "N"))
end
