local addonName, addon = ...
addon.ImportParser = {}
local ImportParser = addon.ImportParser

local MAX_LENGTH = 5 * 1024 * 1024  -- 5MB

-- 데이터 표현식만 허용. 코드 실행 패턴을 거부.
local DANGEROUS_PATTERNS = {
    "require%s*%(", "os%s*%.", "io%s*%.", "loadfile%s*%(",
    "dofile%s*%(", "debug%s*%.", "load%s*%(", "loadstring%s*%(",
    "setfenv%s*%(", "getfenv%s*%(", "rawset%s*%(", "rawget%s*%(",
    "coroutine%s*%.", "function%s+%w", "function%s*%(",
    "while%s+", "repeat%s+", "goto%s+", "for%s+",
}

local VALID_SPECS = {
    DiscPriest=true, HolyPriest=true, RestoDruid=true,
    MistweaverMonk=true, HolyPaladin=true, RestoShaman=true, PresEvoker=true,
}

function ImportParser:Parse(input)
    if type(input) ~= "string" then
        return nil, "입력값이 문자열이 아닙니다."
    end

    if #input == 0 then
        return nil, "입력값이 비어있습니다."
    end

    if #input > MAX_LENGTH then
        return nil, string.format("입력값이 너무 큽니다 (최대 %dMB).", MAX_LENGTH / (1024 * 1024))
    end

    -- Lua 는 대소문자 구분 — `require` 외의 표기(Require 등)는 globals 에 없음.
    -- DANGEROUS_PATTERNS 는 전부 소문자로 정의돼 있으므로 input:lower() 로 5MB 복사본을
    -- 만들 필요 없이 원본에 바로 find 하면 됨. 붙여넣기 프리즈 주원인 중 하나.
    for _, pattern in ipairs(DANGEROUS_PATTERNS) do
        if input:find(pattern) then
            return nil, "보안: 허용되지 않은 패턴 — " .. pattern
        end
    end

    local fn, err = loadstring(input)
    if not fn then
        return nil, "파싱 오류: " .. tostring(err)
    end

    -- Lua 5.1: setfenv 로 빈 환경에서 실행
    setfenv(fn, {})

    local ok, result = pcall(fn)
    if not ok then
        return nil, "실행 오류: " .. tostring(result)
    end

    if type(result) ~= "table" then
        return nil, "결과가 테이블이 아닙니다."
    end

    if result.version ~= 1 then
        return nil, "버전 불일치: version=1 이어야 합니다."
    end

    if type(result.dungeonName) ~= "string" or result.dungeonName == "" then
        return nil, "dungeonName 이 누락되었습니다."
    end

    if type(result.spec) ~= "string" or not VALID_SPECS[result.spec] then
        return nil, "알 수 없는 spec: " .. tostring(result.spec)
    end

    if type(result.bosses) ~= "table" then
        return nil, "bosses 가 누락되었습니다."
    end

    for encID, boss in pairs(result.bosses) do
        if type(encID) ~= "number" then
            return nil, "bosses 키가 숫자가 아닙니다: " .. tostring(encID)
        end
        if type(boss) ~= "table" then
            return nil, "boss 항목이 테이블이 아닙니다: " .. tostring(encID)
        end
        if boss.timeline ~= nil then
            if type(boss.timeline) ~= "table" then
                return nil, "timeline이 테이블이 아닙니다: " .. tostring(encID)
            end
            for i, entry in ipairs(boss.timeline) do
                if type(entry.spellID) ~= "number" then
                    return nil, string.format("timeline[%d].spellID 가 숫자가 아닙니다 (encID=%d)", i, encID)
                end
                if type(entry.offset) ~= "number" then
                    return nil, string.format("timeline[%d].offset 이 숫자가 아닙니다 (encID=%d)", i, encID)
                end
            end
        end
        if boss.reactions ~= nil then
            if type(boss.reactions) ~= "table" then
                return nil, "reactions가 테이블이 아닙니다: " .. tostring(encID)
            end
            for bossSpell, entries in pairs(boss.reactions) do
                if type(bossSpell) ~= "number" then
                    return nil, "reactions 키가 숫자가 아닙니다: " .. tostring(bossSpell)
                end
                if type(entries) ~= "table" then
                    return nil, "reactions 항목이 테이블이 아닙니다"
                end
                for i, entry in ipairs(entries) do
                    if type(entry.spellID) ~= "number" then
                        return nil, string.format("reactions[%d].spellID 가 숫자가 아닙니다", i)
                    end
                    if type(entry.delay) ~= "number" then
                        return nil, string.format("reactions[%d].delay 가 숫자가 아닙니다", i)
                    end
                end
            end
        end
        if boss.leadIns ~= nil then
            if type(boss.leadIns) ~= "table" then
                return nil, "leadIns가 테이블이 아닙니다: " .. tostring(encID)
            end
            for bossSpell, entries in pairs(boss.leadIns) do
                if type(bossSpell) ~= "number" then
                    return nil, "leadIns 키가 숫자가 아닙니다: " .. tostring(bossSpell)
                end
                if type(entries) ~= "table" then
                    return nil, "leadIns 항목이 테이블이 아닙니다"
                end
                for i, entry in ipairs(entries) do
                    if type(entry.spellID) ~= "number" then
                        return nil, string.format("leadIns[%d].spellID 가 숫자가 아닙니다", i)
                    end
                    if type(entry.offset) ~= "number" then
                        return nil, string.format("leadIns[%d].offset 이 숫자가 아닙니다", i)
                    end
                end
            end
        end
    end

    return result, nil
end

function ImportParser:ImportFromTable(data)
    if type(data) ~= "table" then return 0 end
    if data.version ~= 1 then return 0 end
    if type(data.dungeonName) ~= "string" or data.dungeonName == "" then return 0 end
    if type(data.spec) ~= "string" or not VALID_SPECS[data.spec] then return 0 end
    if type(data.bosses) ~= "table" then return 0 end

    local bossCount = 0
    for _ in pairs(data.bosses) do bossCount = bossCount + 1 end
    if bossCount == 0 then return 0 end

    addon.Storage:AddDungeon({
        dungeonName = data.dungeonName,
        spec        = data.spec,
        bosses      = data.bosses,
        sourceURL   = data.sourceURL or "",
    })

    return bossCount
end
