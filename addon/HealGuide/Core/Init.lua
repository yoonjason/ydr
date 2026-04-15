local addonName, addon = ...
-- S1: 전역 HealGuide 제거 — 다른 파일은 모두 local addon 참조

local DEBUG = false

addon.dprint = function(...)
    if DEBUG then print("|cff888888[HG]|r", ...) end
end

local eventFrame = CreateFrame("Frame", "HealGuideEventFrame", UIParent)

local function onAddonLoaded(name)
    if name ~= addonName then return end
    addon.Storage:Init()
    addon.SpecMatcher:Init()
    addon.AlertFrame:Init()
    addon.MainFrame:Init()
    print("|cff00ff00HealGuide|r 로드 완료. /hg 로 설정")
end

local function onPlayerLogin()
    addon.SpecMatcher:Refresh()
end

local function onSpecChanged()
    addon.SpecMatcher:Refresh()
end

local function onEncounterStart(encounterID, encounterName, difficultyID, groupSize)
    addon.EncounterEngine:OnEncounterStart(encounterID, encounterName)
end

local function onEncounterEnd()
    addon.EncounterEngine:OnEncounterEnd()
end

local function onCombatLog()
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
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

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
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        onCombatLog()
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
        local encID = tonumber(args)
        if encID then
            addon.EncounterEngine:TestEncounter(encID)
        else
            print("|cff00ff00HealGuide|r 사용법: /hg test <encounterID>")
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
    else
        print("|cff00ff00HealGuide|r 명령어: /hg, /hg import, /hg test <encID>, " ..
              "/hg lock, /hg mode <reactive|absolute|hybrid>, " ..
              "/hg size <32-128>, /hg pulse <48-160>, " ..
              "/hg tts <on|off>, /hg sound <on|off>, /hg label <on|off>")
    end
end
