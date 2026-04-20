local addonName, addon = ...
-- S1: 전역 HealGuide 제거 — 다른 파일은 모두 local addon 참조

addon.dprint = function(...)
    if addon.Storage and addon.Storage:GetSetting("debugMode") then
        print("|cff888888[HG]|r", ...)
    end
end

-- 메인 이벤트 프레임: 부모 없이 생성 (12.0에서 UIParent 자식 + COMBAT_LOG_EVENT_UNFILTERED 조합이 FORBIDDEN 트리거)
local eventFrame = CreateFrame("Frame")
-- 전투 로그 전용 분리 프레임 (추가 격리)
local clFrame    = CreateFrame("Frame")

-- Forward declaration: onAddonLoaded / onPlayerLogin 내부에서 호출하므로 위에서 local 선언.
-- 실제 함수 본문은 아래쪽의 StaticPopup 블록에서 할당.
local _hgInstallPopupBlocker

local function autoImportGeneratedData()
    if type(HealGuide_Generated) ~= "table" then return end
    local data = HealGuide_Generated
    if not data.spec or not data.bosses then return end

    local ok, count = pcall(function()
        return addon.ImportParser:ImportFromTable(data)
    end)
    if ok and count and count > 0 then
        print(string.format("|cff88ff88[HG]|r 자동 import: %s (%d 보스)", data.dungeonName or "?", count))
    end
end

local function onAddonLoaded(name)
    -- Blizzard_StaticPopup_Game 이 on-demand 로드될 때 블로커 재설치
    if name == "Blizzard_StaticPopup_Game" then
        _hgInstallPopupBlocker()
    end
    if name ~= addonName then return end
    addon.Storage:Init()
    addon.SpecMatcher:Init()
    addon.AlertFrame:Init()
    addon.MainFrame:Init()
    if addon.EncounterTimelineBridge and addon.EncounterTimelineBridge.Init then
        addon.EncounterTimelineBridge:Init()
    end
    if addon.MinimapButton and addon.MinimapButton.Init then
        addon.MinimapButton:Init()
    end
    if addon.TimelineFrame and addon.TimelineFrame.Init then
        addon.TimelineFrame:Init()
    end
    autoImportGeneratedData()
    print("|cff00ff00HealGuide|r 로드 완료. /hg 로 설정")
end

local function onPlayerLogin()
    addon.Storage:InitDualSpec()
    addon.SpecMatcher:Refresh()
    if addon.DungeonMappings and addon.DungeonMappings.ValidateActiveSeason then
        addon.DungeonMappings:ValidateActiveSeason()
    end
    _hgInstallPopupBlocker()
end

local function onSpecChanged()
    addon.SpecMatcher:Refresh()
end

local function onEncounterStart(encounterID, encounterName, difficultyID, groupSize)
    addon.dprint(string.format("ENCOUNTER_START: id=%d name=%s",
        encounterID or -1, tostring(encounterName)))
    addon.EncounterEngine:OnEncounterStart(encounterID, encounterName)
end

local function onEncounterEnd()
    addon.EncounterEngine:OnEncounterEnd()
end

local function onCombatLog()
    local timestamp, subevent, hideCaster,
          sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID, destName, destFlags, destRaidFlags,
          spellID, spellName, spellSchool,
          arg15, arg16 = CombatLogGetCurrentEventInfo()

    if subevent == "SPELL_CAST_SUCCESS" and sourceGUID == UnitGUID("player") and spellID then
        addon.EncounterEngine:OnPlayerCast(spellID)
    end
    addon.EncounterEngine:OnCombatLog(
        timestamp, subevent, hideCaster,
        sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
        destGUID, destName, destFlags, destRaidFlags,
        spellID, spellName, spellSchool, arg15, arg16)
end

local function onZoneChanged()
    addon.EncounterEngine:OnZoneChanged()
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
-- ENCOUNTER_PHASE_UPDATE 는 Midnight(12.0) 에서 미존재. Phase 추적은 추후 UNIT_SPELLCAST 화이트리스트 기반으로 재설계.
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
-- 트래시 알림은 시전 'SUCCEEDED' 가 아닌 'START' 기준으로 → 캐스트 진행 중에 미리 알림.
-- 동일 시전의 START→SUCCEEDED 이중 발화 방지를 위해 SUCCEEDED 는 등록하지 않음.
eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
clFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
clFrame:SetScript("OnEvent", function() onCombatLog() end)

-- Blizzard 기본 팝업 억제 (보호된 함수 호출 경고창 제거)
UIParent:UnregisterEvent("ADDON_ACTION_BLOCKED")
UIParent:UnregisterEvent("ADDON_ACTION_FORBIDDEN")
local blockFrame = CreateFrame("Frame")
blockFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
blockFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blockFrame:SetScript("OnEvent", function(_, event, addonNameArg, funcName)
    addon.dprint(string.format("[HG-block] %s addon=%s func=%s",
        event, tostring(addonNameArg), tostring(funcName)))
end)

-- StaticPopup 경로로 올라오는 "애드온 차단" 팝업 억제.
-- Midnight 12.0 에서 StaticPopup 시스템이 Blizzard_StaticPopup_Game 이라는 on-demand 애드온으로
-- 분리되어, HealGuide ADDON_LOADED 시점에는 StaticPopupDialogs 테이블이 아직 없을 수 있음.
-- 따라서 설치 루틴을 함수화해서 여러 시점에 재시도.
local _hgPopupInstalled = false
_hgInstallPopupBlocker = function()
    local installed = false
    if StaticPopupDialogs then
        for _, key in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
            local entry = StaticPopupDialogs[key]
            if entry and not entry._hgNeutered then
                StaticPopupDialogs[key] = {
                    text         = "",
                    timeout      = 0,
                    whileDead    = true,
                    hideOnEscape = true,
                    showAlert    = false,
                    OnShow       = function(self) self:Hide() end,
                    _hgNeutered  = true,
                }
                installed = true
            end
        end
    end
    if type(StaticPopup_Show) == "function" and not _hgPopupInstalled then
        hooksecurefunc("StaticPopup_Show", function(which)
            if which == "ADDON_ACTION_FORBIDDEN" or which == "ADDON_ACTION_BLOCKED" then
                for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
                    local dlg = _G["StaticPopup" .. i]
                    if dlg and dlg.which == which then dlg:Hide() end
                end
            end
        end)
        _hgPopupInstalled = true
        installed = true
    end
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local dlg = _G["StaticPopup" .. i]
        if dlg and not dlg._hgHooked then
            dlg._hgHooked = true
            dlg:HookScript("OnShow", function(self)
                if self.which == "ADDON_ACTION_FORBIDDEN" or self.which == "ADDON_ACTION_BLOCKED" then
                    self:Hide()
                end
            end)
            installed = true
        end
    end
    return installed
end
_hgInstallPopupBlocker()

local eventHandlers = {
    ADDON_LOADED                  = function(name) onAddonLoaded(name) end,
    PLAYER_LOGIN                  = function() onPlayerLogin() end,
    PLAYER_SPECIALIZATION_CHANGED = function() onSpecChanged() end,
    ENCOUNTER_START               = function(...) onEncounterStart(...) end,
    ENCOUNTER_END                 = function() onEncounterEnd() end,
    PLAYER_ENTERING_WORLD         = function() onZoneChanged() end,
    ZONE_CHANGED_NEW_AREA         = function() onZoneChanged() end,
    CHALLENGE_MODE_START = function(mapID)
        if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
            addon.EncounterEngine:OnChallengeModeStart(mapID)
        end
    end,
    CHALLENGE_MODE_COMPLETED = function()
        addon.EncounterEngine:OnChallengeModeCompleted()
    end,
    UNIT_SPELLCAST_START = function(unit, _, spellID)
        addon.EncounterEngine:OnUnitSpellcast(unit, spellID, "UNIT_SPELLCAST_START")
    end,
    UNIT_SPELLCAST_STOP = function(unit, _, spellID)
        addon.EncounterEngine:OnUnitSpellcastStop(unit, spellID)
    end,
    UNIT_SPELLCAST_INTERRUPTED = function(unit, _, spellID)
        addon.EncounterEngine:OnUnitSpellcastStop(unit, spellID)
    end,
}
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local h = eventHandlers[event]
    if h then h(...) end
end)

SLASH_HEALGUIDE1 = "/hg"
SlashCmdList["HEALGUIDE"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd, args = msg:match("^(%S+)%s*(.*)")
    cmd  = cmd  or ""
    args = args or ""

    if cmd == "" then
        addon.MainFrame:Toggle()
    elseif cmd == "import" then
        addon.ImportDialog:Open()
    elseif cmd == "test" then
        if args == "condition" then
            if addon.ConditionEvaluator and addon.ConditionEvaluator.RunSelfTest then
                addon.ConditionEvaluator:RunSelfTest()
            else
                print("|cff00ff00HealGuide|r ConditionEvaluator 미로드")
            end
            return
        end
        local encID = tonumber(args)
        if encID then
            addon.EncounterEngine:TestEncounter(encID)
        else
            print("|cff00ff00HealGuide|r 사용법: /hg test <encounterID> 또는 /hg test condition")
        end
    elseif cmd == "rankertest" then
        local sub        = args:match("^(%S+)")
        local encID      = tonumber(args)
        local activeSpec = addon.SpecMatcher and addon.SpecMatcher:GetActiveSpec()
        if sub == "cancel" then
            if addon.EncounterEngine:IsRankerTestRunning() then
                addon.EncounterEngine:CancelRankerTest()
            else
                print("|cff00ff00HealGuide|r 진행 중인 랭커 테스트 없음")
            end
        elseif not activeSpec then
            print("|cff00ff00HealGuide|r 힐러 스펙이 아닙니다.")
        elseif not encID then
            print("|cff00ff00HealGuide|r 사용법: /hg rankertest <encounterID> | /hg rankertest cancel")
        elseif not (addon.RankerDataLoader and addon.RankerDataLoader:IsDataAvailable()) then
            print("|cff00ff00HealGuide|r 랭커 데이터 없음 — Mac 앱에서 수집하세요")
        else
            local found = nil
            for _, e in ipairs(addon.RankerDataLoader:GetEntries()) do
                if e._meta and e._meta.spec == activeSpec and e.data and e.data[encID] then
                    found = { _meta = e._meta, data = { [encID] = e.data[encID] } }
                    break
                end
            end
            if found then
                addon.EncounterEngine:TestRankerEntry(found)
            else
                print(string.format("|cff00ff00HealGuide|r 랭커 데이터 없음: spec=%s encID=%d", activeSpec, encID))
            end
        end
    elseif cmd == "lock" then
        addon.AlertFrame:ToggleLock()
        if addon.MainFrame._RefreshSettings then
            addon.MainFrame:_RefreshSettings()
        end
    elseif cmd == "mode" then
        local mode = args:match("^(%S+)")
        if mode == "reactive" or mode == "absolute" or mode == "hybrid" then
            addon.Storage:SetSetting("alertMode", mode)
            print("|cff00ff00HealGuide|r 모드: " .. mode)
        else
            print("|cff00ff00HealGuide|r 사용법: /hg mode <reactive|absolute|hybrid>")
        end
    elseif cmd == "size" then
        local n = tonumber(args)
        if n and n >= 32 and n <= 128 then
            n = math.floor(n)
            addon.Storage:SetSetting("iconBaseSize", n)
            local pulse = addon.Storage:GetSetting("iconPulseSize") or 96
            if pulse < n then
                addon.Storage:SetSetting("iconPulseSize", n)
            end
            addon.AlertFrame:ApplyIconSize()
            print("|cff00ff00HealGuide|r 기본 크기: " .. n)
        else
            print("|cff00ff00HealGuide|r 사용법: /hg size <32-128>")
        end
    elseif cmd == "pulse" then
        local n = tonumber(args)
        local base = addon.Storage:GetSetting("iconBaseSize") or 64
        if n and n >= 48 and n <= 160 and n >= base then
            n = math.floor(n)
            addon.Storage:SetSetting("iconPulseSize", n)
            addon.AlertFrame:ApplyIconSize()
            print("|cff00ff00HealGuide|r 확대 크기: " .. n)
        else
            print("|cff00ff00HealGuide|r 사용법: /hg pulse <48-160> (기본 크기 이상)")
        end
    elseif cmd == "tts" then
        if args == "on" then
            addon.Storage:SetSetting("ttsEnabled", true)
            print("|cff00ff00HealGuide|r TTS: ON")
        elseif args == "off" then
            addon.Storage:SetSetting("ttsEnabled", false)
            print("|cff00ff00HealGuide|r TTS: OFF")
        else
            print("|cff00ff00HealGuide|r 사용법: /hg tts <on|off>")
        end
    elseif cmd == "sound" then
        if args == "on" then
            addon.Storage:SetSetting("soundEnabled", true)
            print("|cff00ff00HealGuide|r 사운드: ON")
        elseif args == "off" then
            addon.Storage:SetSetting("soundEnabled", false)
            print("|cff00ff00HealGuide|r 사운드: OFF")
        else
            print("|cff00ff00HealGuide|r 사용법: /hg sound <on|off>")
        end
    elseif cmd == "lead" then
        local n = tonumber(args)
        if n and n >= 0 and n <= 5 then
            addon.Storage:SetSetting("leadTime", n)
            print(string.format("|cff00ff00HealGuide|r 리드 타임: %.1f초 (다음 인카운터부터 반영)", n))
        else
            print("|cff00ff00HealGuide|r 사용법: /hg lead <0.0-5.0>")
        end
    elseif cmd == "label" then
        if args == "on" then
            addon.Storage:SetSetting("showSpellName", true)
            print("|cff00ff00HealGuide|r 스킬명 표시: ON")
        elseif args == "off" then
            addon.Storage:SetSetting("showSpellName", false)
            print("|cff00ff00HealGuide|r 스킬명 표시: OFF")
        else
            print("|cff00ff00HealGuide|r 사용법: /hg label <on|off>")
        end
    elseif cmd == "pause" then
        addon.EncounterEngine:Pause()
        if addon.MainFrame._RefreshDataTab then addon.MainFrame:_RefreshDataTab() end
    elseif cmd == "resume" then
        addon.EncounterEngine:Resume()
        if addon.MainFrame._RefreshDataTab then addon.MainFrame:_RefreshDataTab() end
    elseif cmd == "history" then
        if addon.CombatHistoryFrame then
            addon.CombatHistoryFrame:Toggle()
        end
    elseif cmd == "reload" then
        print("|cff00ff00HealGuide|r UI 새로고침 중...")
        ReloadUI()
    elseif cmd == "debug" then
        local current = addon.Storage:GetSetting("debugMode")
        addon.Storage:SetSetting("debugMode", not current)
        print("|cff00ff00HealGuide|r 디버그: " .. (not current and "ON" or "OFF"))
        if addon.MainFrame._RefreshSettings then
            addon.MainFrame:_RefreshSettings()
        end
    elseif cmd == "policy" then
        local p = args:match("^(%S+)")
        if p == "off" or p == "merge" or p == "exclusive" then
            addon.Storage:SetSetting("rankerPolicy", p)
            if addon.MainFrame and addon.MainFrame._RefreshRankerTab then
                addon.MainFrame:_RefreshRankerTab()
            end
            print("|cff00ff00HealGuide|r 랭커 정책: " .. p)
        else
            print("|cff00ff00HealGuide|r 사용법: /hg policy <off|merge|exclusive>")
        end
    elseif cmd == "timeline" then
        local sub = args:match("^(%S+)")
        if sub == "on" then
            addon.Storage:SetSetting("timelineVisible", true)
            addon.TimelineFrame:ApplyVisibility()
            print("|cff00ff00HealGuide|r 타임라인: ON")
        elseif sub == "off" then
            addon.Storage:SetSetting("timelineVisible", false)
            addon.TimelineFrame:ApplyVisibility()
            print("|cff00ff00HealGuide|r 타임라인: OFF")
        elseif sub == "horizontal" or sub == "vertical" then
            addon.Storage:SetSetting("timelineOrientation", sub)
            addon.TimelineFrame:ApplyLayout()
            print("|cff00ff00HealGuide|r 타임라인 방향: " .. sub)
        elseif sub == "reset" then
            addon.TimelineFrame:ResetPosition()
            print("|cff00ff00HealGuide|r 타임라인 위치 초기화")
        else
            print("|cff00ff00HealGuide|r 사용법: /hg timeline <on|off|horizontal|vertical|reset>")
        end
    else
        print("|cff00ff00HealGuide|r 명령어: /hg, /hg import, /hg test <encID>, " ..
              "/hg lock, /hg mode <reactive|absolute|hybrid>, " ..
              "/hg size <32-128>, /hg pulse <48-160>, /hg lead <0.0-5.0>, " ..
              "/hg tts <on|off>, /hg sound <on|off>, /hg label <on|off>, " ..
              "/hg policy <off|merge|exclusive>, " ..
              "/hg timeline <on|off|horizontal|vertical|reset>, " ..
              "/hg debug, /hg pause, /hg resume, /hg history, /hg reload")
    end
end
