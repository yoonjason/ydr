-- CallbackHandler-1.0: event/callback dispatcher for WoW addon libraries
-- MIT License (Public Domain – WoWAce community standard)

local MAJOR, MINOR = "CallbackHandler-1.0", 6
local CallbackHandler = LibStub:NewLibrary(MAJOR, MINOR)
if not CallbackHandler then return end

local meta = { __index = function(t, k) rawset(t, k, {}) return rawget(t, k) end }

function CallbackHandler:New(obj, registerName, unregisterName, unregisterAllName)
    registerName       = registerName       or "RegisterCallback"
    unregisterName     = unregisterName     or "UnregisterCallback"
    unregisterAllName  = unregisterAllName  or "UnregisterAllCallbacks"

    local events   = setmetatable({}, meta)
    local registry = { events = events }

    obj[registerName] = function(self, event, method, ...)
        if type(method) ~= "function" then
            local handlerName = method or event
            method = self[handlerName]
            assert(type(method) == "function",
                ("Usage: %s(self, event, method): method %q not found on self"):format(
                    registerName, tostring(handlerName)))
        end
        local args = { ... }
        events[event][self] = { method, args }
    end

    obj[unregisterName] = function(self, event)
        if events[event] then events[event][self] = nil end
    end

    obj[unregisterAllName] = function(self)
        for _, handlers in pairs(events) do
            handlers[self] = nil
        end
    end

    function registry:Fire(event, ...)
        local handlers = rawget(events, event)
        if not handlers then return end
        for target, info in pairs(handlers) do
            local method = info[1]
            local args   = info[2]
            if args and #args > 0 then
                method(target, event, ..., unpack(args))
            else
                method(target, event, ...)
            end
        end
    end

    return registry
end
