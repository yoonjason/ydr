-- LibStub: minimal versioned library registry for WoW addons
-- MIT License (Public Domain – WoWAce community standard)

local LIBSTUB_MAJOR, LIBSTUB_MINOR = "LibStub", 2

local LibStub = _G[LIBSTUB_MAJOR]
if LibStub and LibStub.minor >= LIBSTUB_MINOR then return end

LibStub         = LibStub or { libs = {}, minors = {} }
_G[LIBSTUB_MAJOR] = LibStub
LibStub.minor   = LIBSTUB_MINOR

function LibStub:NewLibrary(major, minor)
    assert(type(major) == "string", "Usage: LibStub:NewLibrary(major, minor)")
    minor = assert(tonumber(minor), "minor version must be a number")
    local existing = self.minors[major]
    if existing and existing >= minor then return nil end
    self.libs[major]   = self.libs[major] or {}
    self.minors[major] = minor
    return self.libs[major], existing
end

function LibStub:GetLibrary(major, silent)
    if not self.libs[major] and not silent then
        error(("Cannot find library instance of %q."):format(tostring(major)), 2)
    end
    return self.libs[major], self.minors[major]
end

function LibStub:IterateLibraries()
    return pairs(self.libs)
end

setmetatable(LibStub, { __call = function(self, ...) return self:GetLibrary(...) end })
