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
    if addon.TimerBarFrame and addon.TimerBarFrame.Init then
        addon.TimerBarFrame:Init()
    end
    autoImportGeneratedData()
    print("|cff00ff00HealGuide|r 로드 완료. /hg 로 설정")
end

local function onPlayerLogin()
    addon.SpecMatcher:Refresh()
end

local function onSpecChanged()
    addon.SpecMatcher:Refresh()
end

local function onEncounterStart(encounterID, encounterName, difficultyID, groupSize)
    print(string.format("|cffffff00[HG]|r ENCOUNTER_START: id=%d name=%s",
        encounterID or -1, tostring(encounterName)))
    addon.EncounterEngine:OnEncounterStart(encounterID, encounterName)
end

local function onEncounterEnd()
    addon.EncounterEngine:OnEncounterEnd()
end

local function onCombatLog()
    local timestamp, subevent, _, sourceGUID, _, sourceFlags, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()
    -- 플레이어 캐스트 추적 (쿨다운 스킵용)
    if subevent == "SPELL_CAST_SUCCESS" and sourceGUID == UnitGUID("player") and spellID then
        addon.EncounterEngine:OnPlayerCast(spellID)
    end
    addon.EncounterEngine:OnCombatLog(CombatLogGetCurrentEventInfo())
end

local function onZoneChanged()
    addon.EncounterEngine:OnZoneChanged()
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("ENCOUNTER_PHASE_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
clFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
clFrame:SetScript("OnEvent", function() onCombatLog() end)

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        onAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then
        onPlayerLogin()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        onSpecChanged()
    elseif event == "ENCOUNTER_START" then
        onEncounterStart(...)
    elseif event == "ENCOUNTER_END" then
        onEncounterEnd()
    elseif event == "ENCOUNTER_PHASE_UPDATE" then
        local phase = ...
        addon.EncounterEngine:OnPhaseUpdate(phase)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        onZoneChanged()
    end
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
    elseif cmd == "lock" then
        addon.AlertFrame:ToggleLock()
        -- 설정 탭이 열려 있으면 체크박스 동기화
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
    elseif cmd == "resume" then
        addon.EncounterEngine:Resume()
    elseif cmd == "history" then
        if addon.CombatHistoryFrame then
            addon.CombatHistoryFrame:Toggle()
        end
    elseif cmd == "debug" then
        local current = addon.Storage:GetSetting("debugMode")
        addon.Storage:SetSetting("debugMode", not current)
        print("|cff00ff00HealGuide|r 디버그: " .. (not current and "ON" or "OFF"))
        if addon.MainFrame._RefreshSettings then
            addon.MainFrame:_RefreshSettings()
        end
    else
        print("|cff00ff00HealGuide|r 명령어: /hg, /hg import, /hg test <encID>, " ..
              "/hg lock, /hg mode <reactive|absolute|hybrid>, " ..
              "/hg size <32-128>, /hg pulse <48-160>, /hg lead <0.0-5.0>, " ..
              "/hg tts <on|off>, /hg sound <on|off>, /hg label <on|off>, " ..
              "/hg debug, /hg pause, /hg resume, /hg history")
    end
end
