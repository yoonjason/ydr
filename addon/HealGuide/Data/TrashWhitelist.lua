local addonName, addon = ...
-- §5B 트래시 알림 화이트리스트. spellID → { responseSpellID, minKeystone, dungeonKey, category }
-- 데이터 근거: docs/mplus_integration_plan.md §4 (2026-04-17 검증).
-- 보스 entry 는 encounterID/스펙별 쿨 매핑 필요하므로 app/ 파이프라인 경유 예정.
addon.TrashWhitelist = {
    -- 4.1 Magisters' Terrace — Lightward Healer
    [1254306] = {
        responseSpellID = 1254306,
        minKeystone     = 7,
        dungeonKey      = "MagistersTerrace",
        category        = "interrupt-critical",
    },

    -- 4.2 Pit of Saron — Dreadpulse Lich
    [1258798] = {
        responseSpellID = 1258798,
        minKeystone     = 10,
        dungeonKey      = "PitOfSaron",
        category        = "party-dmg",
    },

    -- 4.2 Pit of Saron — Rimebone Coldwraith
    [1258437] = {
        responseSpellID = 1258437,
        minKeystone     = 5,
        dungeonKey      = "PitOfSaron",
        category        = "dispel-urgent",
    },

    -- 4.3 Skyreach — Solar Elemental
    -- NOTE: 스펠 이름이 "Solar Orb" 이나 소환 모브명이 "Solar Elemental" 과 불일치할 수 있음
    [1254329] = {
        responseSpellID = 1254329,
        minKeystone     = 10,
        dungeonKey      = "Skyreach",
        category        = "party-dmg",
    },

    -- 4.6 Windrunner's Spire — Bloated Lasher
    [1216963] = {
        responseSpellID = 1216963,
        minKeystone     = 10,
        dungeonKey      = "WindrunnerSpire",
        category        = "tank-buster",
    },

    -- 4.6 Windrunner's Spire — Devoted Woebringer
    [473668] = {
        responseSpellID = 473668,
        minKeystone     = 7,
        dungeonKey      = "WindrunnerSpire",
        category        = "interrupt-critical",
    },

    -- 4.6 Windrunner's Spire — Phantasmal Mystic
    [1216592] = {
        responseSpellID = 1216592,
        minKeystone     = 7,
        dungeonKey      = "WindrunnerSpire",
        category        = "interrupt-critical",
    },

    -- 4.7 Maisara Caverns — Dread Souleater
    [1257088] = {
        responseSpellID = 1257088,
        minKeystone     = 7,
        dungeonKey      = "MaisaraCaverns",
        category        = "interrupt-critical",
    },

    -- 4.7 Maisara Caverns — Ritual Hexxer
    [1256008] = {
        responseSpellID = 1256008,
        minKeystone     = 7,
        dungeonKey      = "MaisaraCaverns",
        category        = "interrupt-critical",
    },

    -- 4.7 Maisara Caverns — Hulking Juggernaut
    [1256047] = {
        responseSpellID = 1256047,
        minKeystone     = 10,
        dungeonKey      = "MaisaraCaverns",
        category        = "party-dmg",
    },

    -- 4.8 Nexus-Point X'enas — Lightwrought (dispel+party-dmg, primary: dispel-urgent)
    [1277557] = {
        responseSpellID = 1277557,
        minKeystone     = 5,
        dungeonKey      = "NexusPointXenas",
        category        = "dispel-urgent",
    },

    -- 4.8 Nexus-Point X'enas — Null Sentinel
    [1252406] = {
        responseSpellID = 1252406,
        minKeystone     = 10,
        dungeonKey      = "NexusPointXenas",
        category        = "party-dmg",
    },
}
