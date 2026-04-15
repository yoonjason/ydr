local addonName, addon = ...
addon.SpecMatcher = {}
local SpecMatcher = addon.SpecMatcher

-- specID → SpecKey 화이트리스트 (GetSpecializationInfo 반환값 기준)
local HEALER_SPECS = {
    [256]  = "DiscPriest",
    [257]  = "HolyPriest",
    [105]  = "RestoDruid",
    [270]  = "MistweaverMonk",
    [65]   = "HolyPaladin",
    [264]  = "RestoShaman",
    [1468] = "PresEvoker",
}

SpecMatcher.activeSpecKey = nil
SpecMatcher.isHealer       = false

function SpecMatcher:Init()
    self:Refresh()
end

function SpecMatcher:Refresh()
    local specIndex = GetSpecialization()
    if not specIndex then
        self.activeSpecKey = nil
        self.isHealer      = false
        return
    end

    local specID = GetSpecializationInfo(specIndex)
    local specKey = HEALER_SPECS[specID]

    if specKey then
        self.activeSpecKey = specKey
        self.isHealer      = true
        addon.dprint("힐러 스펙 감지:", specKey, "(specID=" .. specID .. ")")
    else
        local wasHealer = self.isHealer
        self.activeSpecKey = nil
        self.isHealer      = false
        if wasHealer then
            print("|cff00ff00HealGuide|r 비힐러 스펙으로 변경 — 알림 비활성")
        end
        addon.EncounterEngine:Cancel()
    end
end

function SpecMatcher:GetActiveSpec()
    return self.activeSpecKey
end

function SpecMatcher:IsHealer()
    return self.isHealer
end
