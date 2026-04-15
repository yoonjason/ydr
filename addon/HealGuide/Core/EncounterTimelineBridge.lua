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
    if not reactions or not reactions[bossSpellID] then
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

    for _, entry in ipairs(reactions[bossSpellID]) do
        local playerSpellID = entry.spellID
        local reactionDelay = entry.delay or 0

        -- 핵심: duration 은 "보스 캐스트까지 남은 초". 반응 delay 를 더하고 leadTime 빼면
        -- "지금으로부터 몇 초 뒤에 플레이어 쿨기를 써야 하는가".
        local schedule = duration + reactionDelay - leadTime
        if schedule > 0 then
            local t = C_Timer.NewTimer(schedule, function()
                engine:TriggerAlert(playerSpellID, "native")
            end)
            table.insert(engine.pendingTimers, t)
            scheduledCount = scheduledCount + 1
        else
            -- 너무 늦었음(이미 지나감) → 즉시 실행
            engine:TriggerAlert(playerSpellID, "native-immediate")
            scheduledCount = scheduledCount + 1
        end
    end

    print(string.format("|cff88ff88[HG-NT]|r boss spellID=%d duration=%.1f → %d개 플레이어 알림 예약 (lead=%.1f)",
        bossSpellID, duration, scheduledCount, leadTime))
end
