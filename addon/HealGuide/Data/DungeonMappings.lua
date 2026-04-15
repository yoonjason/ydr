local addonName, addon = ...
addon.DungeonMappings = {}
local DungeonMappings = addon.DungeonMappings

-- encounterID → instanceMapID (GetInstanceInfo() 4번째 반환값)
-- The War Within 시즌 1 기준. 시즌마다 갱신 필요.

DungeonMappings.data = {
    -- The Stonevault (instanceMapID 2660)
    [3056] = 2660,  -- Emberdawn
    [3057] = 2660,  -- Void Speaker Eirich
    [3058] = 2660,  -- Skarmorak
    [3059] = 2660,  -- The Darkness

    -- Ara-Kara, City of Echoes (instanceMapID 2634)
    [3023] = 2634,  -- Avanoxx
    [3024] = 2634,  -- Anub'zekt
    [3025] = 2634,  -- Ki'katal the Harvester

    -- City of Threads (instanceMapID 2651)
    [3026] = 2651,  -- Orator Krix'vizk
    [3027] = 2651,  -- The Coaglamation
    [3028] = 2651,  -- Fangs of the Queen

    -- The Dawnbreaker (instanceMapID 2652)
    [3029] = 2652,  -- Rasha'nan
    [3030] = 2652,  -- Vigilant Steward, Zorvaldas
    [3031] = 2652,  -- Speaker Shadowcrown

    -- Mists of Tirna Scithe (instanceMapID 2290, S1 로테이션)
    [2441] = 2290,  -- Ingra Maloch
    [2442] = 2290,  -- Mistcaller
    [2444] = 2290,  -- Tred'ova

    -- The Necrotic Wake (instanceMapID 2286, S1 로테이션)
    [2433] = 2286,  -- Blightbone
    [2434] = 2286,  -- Amarth, the Harvester
    [2435] = 2286,  -- Surgeon Stitchflesh
    [2437] = 2286,  -- Nalthor the Rimebinder
}

function DungeonMappings:GetInstanceMapID(encounterID)
    return self.data[encounterID]
end
