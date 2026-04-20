-- LibSharedMedia-3.0: shared registry for fonts, sounds, textures, and backgrounds
-- MIT License (Public Domain – WoWAce community standard)

local MAJOR, MINOR = "LibSharedMedia-3.0", 8
local LibSharedMedia = LibStub:NewLibrary(MAJOR, MINOR)
if not LibSharedMedia then return end

-- ── Media type constants ──────────────────────────────────────────────────────

LibSharedMedia.MediaType = {
    BACKGROUND = "background",
    BORDER     = "border",
    FONT       = "font",
    SOUND      = "sound",
    STATUSBAR  = "statusbar",
}

local _registry   = {}  -- [mediaType][name] = data
local _callbacks  = {}  -- unused in this minimal impl (kept for API compat)

local function ensureType(mediaType)
    if not _registry[mediaType] then _registry[mediaType] = {} end
end

-- ── Core API ─────────────────────────────────────────────────────────────────

-- Register a named media entry. Returns true if the name is new.
function LibSharedMedia:Register(mediaType, name, data)
    assert(type(mediaType) == "string", "mediaType must be string")
    assert(type(name)      == "string", "name must be string")
    ensureType(mediaType)
    local isNew = _registry[mediaType][name] == nil
    _registry[mediaType][name] = data
    return isNew
end

-- Fetch data for a named media entry.
-- If name is not found and noDefault is false, returns the first available entry.
function LibSharedMedia:Fetch(mediaType, name, noDefault)
    local reg = _registry[mediaType]
    if not reg then return nil end
    if reg[name] then return reg[name] end
    if noDefault then return nil end
    local _, v = next(reg)
    return v
end

function LibSharedMedia:IsValid(mediaType, name)
    local reg = _registry[mediaType]
    return reg ~= nil and reg[name] ~= nil
end

-- Returns a reference to the raw hash table for a media type.
function LibSharedMedia:HashTable(mediaType)
    ensureType(mediaType)
    return _registry[mediaType]
end

-- Returns a sorted list of registered names for a media type.
function LibSharedMedia:List(mediaType)
    local reg = _registry[mediaType]
    if not reg then return {} end
    local t = {}
    for k in pairs(reg) do t[#t + 1] = k end
    table.sort(t)
    return t
end

-- ── Default WoW media ─────────────────────────────────────────────────────────

-- Fonts (paths relative to WoW game directory)
LibSharedMedia:Register("font", "Friz Quadrata TT", "Fonts\\FRIZQT__.TTF")
LibSharedMedia:Register("font", "Arial Narrow",     "Fonts\\ARIALN.TTF")
LibSharedMedia:Register("font", "Morpheus",         "Fonts\\MORPHEUS.TTF")
LibSharedMedia:Register("font", "Skurri",           "Fonts\\skurri.TTF")
LibSharedMedia:Register("font", "Expressway",       "Fonts\\FULLMOON.TTF")

-- Sounds (paths relative to WoW game directory; used with PlaySoundFile)
LibSharedMedia:Register("sound", "None",           "")
LibSharedMedia:Register("sound", "ReadyCheck",     "Sound\\Interface\\ReadyCheck.ogg")
LibSharedMedia:Register("sound", "Alarm Clock",    "Sound\\Interface\\AlarmClockWarning3.ogg")
LibSharedMedia:Register("sound", "Level Up",       "Sound\\Interface\\LevelUp.ogg")
LibSharedMedia:Register("sound", "Raid Warning",   "Sound\\Doodad\\BellTollAlliance.wav")
LibSharedMedia:Register("sound", "PVP Flag",       "Sound\\Spells\\PVPFlagTaken.ogg")
