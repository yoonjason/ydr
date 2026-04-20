-- AceDB-3.0: SavedVariable-backed profile database for WoW addons
-- MIT License (Public Domain – WoWAce community standard)

local MAJOR, MINOR = "AceDB-3.0", 26
local AceDB = LibStub:NewLibrary(MAJOR, MINOR)
if not AceDB then return end

local CallbackHandler = LibStub("CallbackHandler-1.0")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function copyTable(src, dest)
    dest = dest or {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = copyTable(v)
        else
            dest[k] = v
        end
    end
    return dest
end

-- Fill nil keys in tbl from defaults (recursive). Does NOT overwrite existing values.
local function initDefaults(tbl, defaults)
    if type(defaults) ~= "table" then return end
    for k, v in pairs(defaults) do
        if tbl[k] == nil then
            if type(v) == "table" then
                tbl[k] = copyTable(v)
            else
                tbl[k] = v
            end
        elseif type(v) == "table" and type(tbl[k]) == "table" then
            initDefaults(tbl[k], v)
        end
    end
end

-- ── db instance methods ───────────────────────────────────────────────────────

local db_methods   = {}
db_methods.__index = db_methods

function db_methods:SetProfile(name)
    assert(type(name) == "string", "name must be a string")
    local old = self.keys.profile
    if old == name then return end

    self.sv.profiles[name] = self.sv.profiles[name] or {}
    initDefaults(self.sv.profiles[name], self.defaults.profile or {})

    local oldProfile   = self.profile
    self.keys.profile  = name
    self.sv.profileKeys[self.charKey] = name
    self.profile       = self.sv.profiles[name]

    self.callbacks:Fire("OnProfileChanged", self, name, old, oldProfile)
end

function db_methods:GetCurrentProfile()
    return self.keys.profile
end

function db_methods:GetProfiles(result)
    result = result or {}
    for name in pairs(self.sv.profiles) do
        result[#result + 1] = name
    end
    table.sort(result)
    return result
end

-- Copy another profile's data INTO the current profile.
function db_methods:CopyProfile(fromName, silent)
    assert(type(fromName) == "string", "fromName must be a string")
    local currentName = self.keys.profile
    assert(fromName ~= currentName, "cannot copy from current profile onto itself")
    local source = self.sv.profiles[fromName]
    assert(source, "source profile not found: " .. fromName)

    local dest = self.sv.profiles[currentName]
    for k in pairs(dest) do dest[k] = nil end
    copyTable(source, dest)
    initDefaults(dest, self.defaults.profile or {})
    self.profile = dest

    if not silent then
        self.callbacks:Fire("OnProfileCopied", self, fromName, currentName)
    end
end

function db_methods:DeleteProfile(name, silent)
    assert(type(name) == "string", "name must be a string")
    assert(name ~= self.keys.profile, "cannot delete the active profile")
    self.sv.profiles[name] = nil
    if not silent then
        self.callbacks:Fire("OnProfileDeleted", self, name)
    end
end

function db_methods:ResetProfile(noCallback)
    local name    = self.keys.profile
    local profile = self.sv.profiles[name]
    for k in pairs(profile) do profile[k] = nil end
    initDefaults(profile, self.defaults.profile or {})
    self.profile = profile
    if not noCallback then
        self.callbacks:Fire("OnProfileReset", self, name)
    end
end

-- ── AceDB:New ────────────────────────────────────────────────────────────────

function AceDB:New(svName, defaults, defaultProfile)
    assert(type(svName) == "string", "svName must be a string")

    -- Ensure the SavedVariable global table exists.
    if type(_G[svName]) ~= "table" then _G[svName] = {} end
    local sv = _G[svName]

    sv.profiles    = sv.profiles    or {}
    sv.profileKeys = sv.profileKeys or {}
    sv.global      = sv.global      or {}

    -- Build the per-character key used to look up the assigned profile.
    local charName  = (UnitName and UnitName("player")) or "Unknown"
    local realmName = (GetRealmName and GetRealmName()) or "Unknown"
    local charKey   = charName .. " - " .. realmName

    -- Determine initial profile name.
    local profileName
    if defaultProfile == true then
        profileName = sv.profileKeys[charKey] or charKey
    elseif type(defaultProfile) == "string" then
        profileName = sv.profileKeys[charKey] or defaultProfile
    else
        profileName = sv.profileKeys[charKey] or "Default"
    end

    sv.profileKeys[charKey]    = profileName
    sv.profiles[profileName]   = sv.profiles[profileName] or {}

    -- Apply defaults.
    initDefaults(sv.profiles[profileName], (defaults and defaults.profile) or {})
    initDefaults(sv.global, (defaults and defaults.global) or {})

    local db = setmetatable({
        sv       = sv,
        defaults = defaults or {},
        keys     = { profile = profileName },
        charKey  = charKey,
        profile  = sv.profiles[profileName],
        global   = sv.global,
    }, db_methods)

    db.callbacks = CallbackHandler:New(db)

    return db
end
