-- HealGuide Main
--
-- 이 파일은 최소 스켈레톤입니다.
-- 실제 구현은 PROJECT_PLAN.md Phase 3 에서 Claude Code 가 채워 넣습니다.
--
-- 현재 상태:
--   - 이벤트 등록 자리만 확보
--   - 실제 매칭/알림 로직은 TODO

local addonName = ...
local HealGuide = {}
_G[addonName] = HealGuide

-- Saved variables 기본값
local defaults = {
    enabled = true,
    soundEnabled = true,
    framePosition = { x = 0, y = 200 },
    displaySeconds = 2.0,
}

-- 현재 활성 스펙/인카운터 (런타임)
HealGuide.state = {
    activeSpec = nil,
    activeEncounter = nil,
}

-- ---- 이벤트 프레임 ----
local frame = CreateFrame("Frame", "HealGuideEventFrame", UIParent)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded == addonName then
            HealGuide:OnLoaded()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        HealGuide:DetectSpec()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        HealGuide:DetectSpec()
    elseif event == "ENCOUNTER_START" then
        local encounterID, encounterName = ...
        HealGuide:OnEncounterStart(encounterID, encounterName)
    elseif event == "ENCOUNTER_END" then
        HealGuide:OnEncounterEnd()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HealGuide:OnCombatLogEvent(CombatLogGetCurrentEventInfo())
    end
end)

-- ---- TODO: 실제 구현 ----

function HealGuide:OnLoaded()
    HealGuideDB = HealGuideDB or {}
    for k, v in pairs(defaults) do
        if HealGuideDB[k] == nil then
            HealGuideDB[k] = v
        end
    end
    print("|cff00ff00HealGuide|r loaded (skeleton)")
end

function HealGuide:DetectSpec()
    -- TODO: GetSpecializationInfo(GetSpecialization()) 로 현재 스펙 감지
    -- HGPT_Data[specKey] 가 있으면 self.state.activeSpec = specKey
end

function HealGuide:OnEncounterStart(encounterID, encounterName)
    -- TODO: self.state.activeEncounter = encounterID
    -- 활성화된 데이터 블록 찾기
end

function HealGuide:OnEncounterEnd()
    -- TODO: 대기 타이머 취소, 상태 리셋
end

function HealGuide:OnCombatLogEvent(timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, ...)
    -- TODO: subevent == "SPELL_CAST_START" 또는 "SPELL_CAST_SUCCESS" 이고
    --       sourceFlags 가 hostile 이며
    --       HGPT_Data[activeSpec][activeEncounter][spellID] 매칭 시
    --       각 { spellID, delay } 를 C_Timer.After 로 예약
end

function HealGuide:ShowReminder(spellID)
    -- TODO: 화면에 아이콘 + 이름 + 소리 표시
end

-- ---- 슬래시 명령어 ----
SLASH_HEALGUIDE1 = "/hg"
SlashCmdList["HEALGUIDE"] = function(msg)
    msg = msg or ""
    if msg == "test" then
        print("|cff00ff00HealGuide|r test (TODO)")
    else
        print("|cff00ff00HealGuide|r commands: /hg test")
    end
end
