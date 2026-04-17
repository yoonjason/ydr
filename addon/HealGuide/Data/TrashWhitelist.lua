local addonName, addon = ...
-- §5B 보스 + 트래시 통합 화이트리스트. spellID → { responseSpellID, minKeystone, dungeonKey, category }
-- 데이터 근거: docs/mplus_integration_plan.md §4 (2026-04-17 검증).
-- 트래시 entry 는 OnUnitSpellcast (UNIT_SPELLCAST_* nameplate 필터) 경유.
-- 보스 entry 도 동일 경로로 작동 — 보스 캐스트도 nameplate 에 반영되므로 whitelist 조회 성립.
-- 추후 encounterID/스펙별 쿨 매핑 정교화는 app/ 파이프라인 경유 예정.
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

    -- === 보스 엔트리 (§4 "보스" 행) ===
    -- minKeystone 정책: interrupt-critical=7 / dispel-urgent=5 / tank-buster=10 / party-dmg=10

    -- 4.1 Magisters' Terrace — Arcanotron Custos (보스) — Ethereal Shackles
    [1214038] = {
        responseSpellID = 1214038,
        minKeystone     = 5,
        dungeonKey      = "MagistersTerrace",
        category        = "dispel-urgent",
    },

    -- 4.1 Magisters' Terrace — Degentrius (보스) — Devouring Entropy
    [1215897] = {
        responseSpellID = 1215897,
        minKeystone     = 10,
        dungeonKey      = "MagistersTerrace",
        category        = "party-dmg",
    },

    -- 4.2 Pit of Saron — Scourgelord Tyrannus (보스) — Festering Pulse
    [1262997] = {
        responseSpellID = 1262997,
        minKeystone     = 10,
        dungeonKey      = "PitOfSaron",
        category        = "party-dmg",
    },

    -- 4.3 Skyreach — Araknath (보스) — Supernova
    [154135] = {
        responseSpellID = 154135,
        minKeystone     = 10,
        dungeonKey      = "Skyreach",
        category        = "party-dmg",
    },

    -- 4.3 Skyreach — High Sage Viryx (보스) — Solar Blast
    [154396] = {
        responseSpellID = 154396,
        minKeystone     = 10,
        dungeonKey      = "Skyreach",
        category        = "tank-buster",
    },

    -- 4.4 Seat of the Triumvirate — Saprish (보스) — Dread Screech
    [248831] = {
        responseSpellID = 248831,
        minKeystone     = 7,
        dungeonKey      = "SeatOfTriumvirate",
        category        = "interrupt-critical",
    },

    -- 4.4 Seat of the Triumvirate — Zuraal the Ascended (보스) — Crashing Void
    [1263297] = {
        responseSpellID = 1263297,
        minKeystone     = 10,
        dungeonKey      = "SeatOfTriumvirate",
        category        = "party-dmg",
    },

    -- 4.4 Seat of the Triumvirate — Viceroy Nezhar (보스) — Collapsing Void
    [1263529] = {
        responseSpellID = 1263529,
        minKeystone     = 10,
        dungeonKey      = "SeatOfTriumvirate",
        category        = "party-dmg",
    },

    -- 4.5 Algeth'ar Academy — Overgrown Ancient (보스) — Healing Touch
    [396640] = {
        responseSpellID = 396640,
        minKeystone     = 7,
        dungeonKey      = "AlgetharAcademy",
        category        = "interrupt-critical",
    },

    -- 4.5 Algeth'ar Academy — Overgrown Ancient (보스) — Lasher Toxin
    [389813] = {
        responseSpellID = 389813,
        minKeystone     = 5,
        dungeonKey      = "AlgetharAcademy",
        category        = "dispel-urgent",
    },

    -- 4.5 Algeth'ar Academy — Echo of Doragosa (보스) — Overwhelming Power
    [389011] = {
        responseSpellID = 389011,
        minKeystone     = 10,
        dungeonKey      = "AlgetharAcademy",
        category        = "party-dmg",
    },

    -- 4.6 Windrunner Spire — Emberdawn (보스) — Burning Gale
    [465904] = {
        responseSpellID = 465904,
        minKeystone     = 10,
        dungeonKey      = "WindrunnerSpire",
        category        = "party-dmg",
    },
    -- skip: 4.6 Windrunner Spire — Restless Heart — Bolt Gale
    --   이유: mplus_integration_plan.md §4.6 에 spellID 미기재 (wiki 링크만 있음). ID 확정 전까지 제외.

    -- 4.7 Maisara Caverns — Vordaza (보스) — Necrotic Convergence
    [1250708] = {
        responseSpellID = 1250708,
        minKeystone     = 10,
        dungeonKey      = "MaisaraCaverns",
        category        = "party-dmg",
    },

    -- 4.8 Nexus-Point X'enas — Lothraxion (보스) — Divine Guile (interrupt-critical + party-dmg, primary: interrupt-critical)
    [1257595] = {
        responseSpellID = 1257595,
        minKeystone     = 7,
        dungeonKey      = "NexusPointXenas",
        category        = "interrupt-critical",
    },
}
