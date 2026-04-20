-- LibDualSpec-1.0: automatic profile swapping on talent specialization change
-- MIT License (Public Domain – WoWAce community standard)

local MAJOR, MINOR = "LibDualSpec-1.0", 14
local LibDualSpec = LibStub:NewLibrary(MAJOR, MINOR)
if not LibDualSpec then return end

local function getActiveSpecIndex()
    if GetSpecialization then
        return GetSpecialization() or 1
    end
    return 1
end

-- EnhanceDatabase(db, name)
-- Adds dual-spec profile swapping to an AceDB database.
-- When the player switches talent specs, the db switches to the stored profile
-- for that spec (if configured by the player).
function LibDualSpec:EnhanceDatabase(db, name)
    assert(db and db.sv, "db must be an AceDB instance")

    local sv     = db.sv
    local charKey = db.charKey

    sv.dualSpec         = sv.dualSpec or {}
    sv.dualSpec[charKey] = sv.dualSpec[charKey] or {}

    local specMap = sv.dualSpec[charKey]

    local function swapIfNeeded()
        local spec = getActiveSpecIndex()
        local targetProfile = specMap[spec]
        if targetProfile and targetProfile ~= db:GetCurrentProfile() then
            db:SetProfile(targetProfile)
        end
    end

    -- ── Public additions to db ────────────────────────────────────────────────

    -- Returns the profile assigned to a spec slot (1 or 2). Defaults to current spec.
    db.GetDualSpecProfile = function(self, specIndex)
        return specMap[specIndex or getActiveSpecIndex()]
    end

    -- Assigns a profile to a spec slot (1 or 2). Defaults to current spec.
    db.SetDualSpecProfile = function(self, profileName, specIndex)
        specMap[specIndex or getActiveSpecIndex()] = profileName
    end

    -- True if at least one spec slot has a profile assigned.
    db.IsDualSpecEnabled = function(self)
        return specMap[1] ~= nil or specMap[2] ~= nil
    end

    -- ── Event listener ────────────────────────────────────────────────────────

    local watchFrame = CreateFrame("Frame")
    watchFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    watchFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    watchFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "ACTIVE_TALENT_GROUP_CHANGED" or unit == "player" then
            swapIfNeeded()
        end
    end)

    -- Check immediately (player may have already loaded with a different spec).
    -- Defer to next frame so AceDB callbacks can be registered first.
    local init = CreateFrame("Frame")
    init:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        swapIfNeeded()
    end)
end
