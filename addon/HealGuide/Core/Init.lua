local addonName, addon = ...
HealGuide = addon

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
    cmd = cmd or ""
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
    elseif cmd == "mode" then
        local mode = args:match("^(%S+)")
        if mode == "reactive" or mode == "absolute" or mode == "hybrid" then
            addon.Storage:SetSetting("alertMode", mode)
            print("|cff00ff00HealGuide|r 모드: " .. mode)
        else
            print("|cff00ff00HealGuide|r 사용법: /hg mode <reactive|absolute|hybrid>")
        end
    else
        print("|cff00ff00HealGuide|r 명령어: /hg, /hg import, /hg test <encID>, /hg lock, /hg mode <reactive|absolute|hybrid>")
    end
end
