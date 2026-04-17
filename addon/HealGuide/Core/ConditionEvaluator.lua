local addonName, addon = ...
addon.ConditionEvaluator = {}
local Evaluator = addon.ConditionEvaluator

-- Phase A 런타임 조건 엔진.
-- 평가 시점 원칙: 조건 평가는 항상 "발화 시점(타이머 콜백 진입 직전)" 에 수행.
-- leadIn 예약(8초 전)에서 캡처한 condition 을 타이머 콜백 안에서 ShouldFire 로 검사.
-- 이유: 파티 HP 등 동적 상태는 발화 순간의 값이 의미 있음.

local MAX_DEPTH = 5

local ALLOWED_OPS = {
    lt = true, lte = true, gt = true, gte = true, eq = true,
    ["and"] = true, ["or"] = true, ["not"] = true,
}

-- Phase A 축소 화이트리스트.
-- tankDebuffStack, bossPhase 는 Phase B 에서 C_UnitAuras / ENCOUNTER_PHASE_UPDATE 로 재도입.
local ALLOWED_FIELDS = {
    partyHPAvg           = true,
    partyHPMin           = true,
    tankHP               = true,
    playerMana           = true,
    spellOnCooldown      = true,
    encounterTimeElapsed = true,
    raidSize             = true,
    bossHP               = true,
    bossPhase            = true,
    keystoneLevel        = true,
    dungeonKey           = true,
    affixActive          = true,
}

local Collector = {}

function Collector.partyHPAvg()
    local unitCount = GetNumGroupMembers()
    if unitCount == 0 then
        local maxHP = UnitHealthMax("player")
        if maxHP and maxHP > 0 then
            return UnitHealth("player") / maxHP
        end
        return 1.0
    end
    local total, count = 0, 0
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, unitCount do
        local unit = prefix .. i
        local maxHP = UnitHealthMax(unit)
        if maxHP and maxHP > 0 then
            total = total + UnitHealth(unit) / maxHP
            count = count + 1
        end
    end
    return count > 0 and (total / count) or 1.0
end

function Collector.partyHPMin()
    local unitCount = GetNumGroupMembers()
    if unitCount == 0 then
        local maxHP = UnitHealthMax("player")
        return (maxHP and maxHP > 0) and (UnitHealth("player") / maxHP) or 1.0
    end
    local minimum = 1.0
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, unitCount do
        local unit = prefix .. i
        local maxHP = UnitHealthMax(unit)
        if maxHP and maxHP > 0 then
            local ratio = UnitHealth(unit) / maxHP
            if ratio < minimum then minimum = ratio end
        end
    end
    return minimum
end

-- S4: 탱 미탐지/사망 시 nil 반환 → fallback 발화 (탱이 죽어도 힐 알림 유지)
function Collector.tankHP()
    local unitCount = GetNumGroupMembers()
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, unitCount do
        local unit = prefix .. i
        if UnitGroupRolesAssigned(unit) == "TANK" then
            local maxHP = UnitHealthMax(unit)
            if maxHP and maxHP > 0 then
                return UnitHealth(unit) / maxHP
            end
        end
    end
    return nil
end

function Collector.playerMana()
    local current = UnitPower("player", Enum.PowerType.Mana)
    local maximum = UnitPowerMax("player", Enum.PowerType.Mana)
    return (maximum and maximum > 0) and (current / maximum) or 1.0
end

-- B1: enable == 1 체크로 GCD 와 실제 쿨다운 구분
function Collector.spellOnCooldown(spellID)
    if not spellID then return 0 end
    local start, duration, enable = GetSpellCooldown(spellID)
    if start and start > 0 and duration and duration > 0 and enable == 1 then
        return 1
    end
    return 0
end

function Collector.encounterTimeElapsed()
    local engine = addon.EncounterEngine
    if not engine or not engine.encounterStartTime then return 0 end
    return GetTime() - engine.encounterStartTime
end

function Collector.raidSize()
    return GetNumGroupMembers()
end

function Collector.bossHP()
    local engine = addon.EncounterEngine
    if not engine then return nil end
    return engine:GetBossHP()
end

function Collector.bossPhase()
    local engine = addon.EncounterEngine
    if not engine then return nil end
    return engine.currentPhase or 1
end

local function collectRequiredFields(node, fields)
    if not node then return end
    if node.field then
        fields[node.field] = true
    end
    if node.operands then
        for _, operand in ipairs(node.operands) do
            collectRequiredFields(operand, fields)
        end
    end
end

-- BuildContext 는 리프 평가 시점에 동적으로 계산하는 필드(spellOnCooldown)를 제외하고
-- condition 트리에서 참조된 정적 필드만 미리 수집. tankHP 는 nil 반환 가능.
function Evaluator:BuildContext(condition)
    local required = {}
    collectRequiredFields(condition, required)

    local context = {}
    for field in pairs(required) do
        if field == "partyHPAvg" then
            context[field] = Collector.partyHPAvg()
        elseif field == "partyHPMin" then
            context[field] = Collector.partyHPMin()
        elseif field == "tankHP" then
            context[field] = Collector.tankHP()
        elseif field == "playerMana" then
            context[field] = Collector.playerMana()
        elseif field == "encounterTimeElapsed" then
            context[field] = Collector.encounterTimeElapsed()
        elseif field == "raidSize" then
            context[field] = Collector.raidSize()
        elseif field == "bossHP" then
            context[field] = Collector.bossHP()
        elseif field == "bossPhase" then
            context[field] = Collector.bossPhase()
        elseif field == "keystoneLevel" then
            context[field] = addon.EncounterEngine.keystoneLevel or 0
        elseif field == "dungeonKey" then
            context.dungeonKey = addon.EncounterEngine.activeDungeonKey or ""
        elseif field == "affixActive" then
            context.activeAffixIDs = addon.EncounterEngine.activeAffixIDs or {}
        end
        -- spellOnCooldown 은 node.spellID 가 노드마다 다르므로 리프 평가 시점에 직접 호출
    end
    return context
end

-- 반환: true/false = 조건 충족/미충족, nil = 평가 실패(fallback 트리거)
function Evaluator:Evaluate(node, context, depth)
    depth = depth or 0
    if depth > MAX_DEPTH then
        addon.dprint("ConditionEvaluator: 최대 깊이 초과 depth=" .. depth)
        return nil
    end

    if type(node) ~= "table" or not ALLOWED_OPS[node.op] then
        addon.dprint("ConditionEvaluator: 허용되지 않는 op=" .. tostring(node and node.op))
        return nil
    end

    if node.op == "and" then
        if type(node.operands) ~= "table" or #node.operands == 0 then return nil end
        local hasNil = false
        for _, operand in ipairs(node.operands) do
            local result = self:Evaluate(operand, context, depth + 1)
            if result == false then return false end
            if result == nil then hasNil = true end
        end
        if hasNil then return nil end
        return true

    elseif node.op == "or" then
        -- C2: nil 이 true 보다 약하게 — true 가 있으면 즉시 true, 모두 false/nil 일 때만 nil 체크
        if type(node.operands) ~= "table" or #node.operands == 0 then return nil end
        local hasNil = false
        for _, operand in ipairs(node.operands) do
            local result = self:Evaluate(operand, context, depth + 1)
            if result == true then return true end
            if result == nil then hasNil = true end
        end
        if hasNil then return nil end
        return false

    elseif node.op == "not" then
        if type(node.operands) ~= "table" or #node.operands ~= 1 then return nil end
        local result = self:Evaluate(node.operands[1], context, depth + 1)
        if result == nil then return nil end
        return not result
    end

    -- 리프 노드
    if not ALLOWED_FIELDS[node.field] then
        addon.dprint("ConditionEvaluator: 허용되지 않는 field=" .. tostring(node.field))
        return nil
    end

    -- C1: spellOnCooldown 은 eq 전용
    if node.field == "spellOnCooldown" then
        if node.op ~= "eq" then
            addon.dprint("ConditionEvaluator: spellOnCooldown 은 eq 전용")
            return nil
        end
        if not node.spellID then
            addon.dprint("ConditionEvaluator: spellOnCooldown 에 spellID 누락")
            return nil
        end
        local cooldownValue = Collector.spellOnCooldown(node.spellID)
        local expected = (node.value == 1) and 1 or 0
        return cooldownValue == expected
    end

    if node.field == "dungeonKey" then
        if node.op ~= "eq" then
            addon.dprint("ConditionEvaluator: dungeonKey 는 eq 전용")
            return nil
        end
        return tostring(context.dungeonKey or "") == tostring(node.value)
    end

    if node.field == "affixActive" then
        if node.op ~= "eq" then
            addon.dprint("ConditionEvaluator: affixActive 는 eq 전용")
            return nil
        end
        if not node.affixID then
            addon.dprint("ConditionEvaluator: affixActive 에 affixID 누락")
            return nil
        end
        local affixIDs = context.activeAffixIDs or {}
        for _, id in ipairs(affixIDs) do
            if id == node.affixID then return true end
        end
        return false
    end

    local lhs = context[node.field]
    if lhs == nil then
        -- tankHP fallback 등 정상적인 nil 반환
        return nil
    end

    local rhs = node.value
    if type(rhs) ~= "number" then return nil end

    if     node.op == "lt"  then return lhs <  rhs
    elseif node.op == "lte" then return lhs <= rhs
    elseif node.op == "gt"  then return lhs >  rhs
    elseif node.op == "gte" then return lhs >= rhs
    elseif node.op == "eq"  then return lhs == rhs
    end
    return nil
end

-- condition = nil → 무조건 true (하위 호환)
-- 평가 실패(nil) → fallback 적용.
-- fallback 우선순위: entry-level 인자 > Storage conditionFallback 설정.
function Evaluator:ShouldFire(condition, fallback)
    if condition == nil then return true end

    local function resolveFallback()
        if fallback ~= nil then return fallback end
        if addon.Storage then return addon.Storage:GetSetting("conditionFallback") end
        return true
    end

    local ok, context = pcall(function() return self:BuildContext(condition) end)
    if not ok then
        addon.dprint("ConditionEvaluator: BuildContext 실패, fallback 적용")
        return resolveFallback() and true or false
    end

    local ok2, result = pcall(function() return self:Evaluate(condition, context, 0) end)
    if not ok2 then
        addon.dprint("ConditionEvaluator: Evaluate 예외, fallback 적용")
        return resolveFallback() and true or false
    end
    if result == nil then
        addon.dprint("ConditionEvaluator: 평가 결과 nil, fallback 적용")
        return resolveFallback() and true or false
    end
    return result
end

-- 자체 테스트 (N1: check 로 rename, C5: deepNode 깊이 재계산)
function Evaluator:RunSelfTest()
    local pass, fail = 0, 0
    local function check(label, got, expected)
        if got == expected then
            pass = pass + 1
        else
            fail = fail + 1
            print(string.format("|cffff4444[HG-CE FAIL]|r %s: got=%s expected=%s",
                label, tostring(got), tostring(expected)))
        end
    end

    local ctx = {
        partyHPAvg = 0.5,
        partyHPMin = 0.3,
        playerMana = 0.8,
        tankHP     = 0.9,
        encounterTimeElapsed = 45,
        raidSize   = 5,
    }

    check("lt true",  self:Evaluate({op="lt",  field="partyHPAvg", value=0.6}, ctx, 0), true)
    check("lt false", self:Evaluate({op="lt",  field="partyHPAvg", value=0.4}, ctx, 0), false)
    check("lte true", self:Evaluate({op="lte", field="partyHPAvg", value=0.5}, ctx, 0), true)
    check("gt true",  self:Evaluate({op="gt",  field="playerMana", value=0.3}, ctx, 0), true)
    check("gte true", self:Evaluate({op="gte", field="playerMana", value=0.8}, ctx, 0), true)
    check("eq true",  self:Evaluate({op="eq",  field="raidSize",   value=5},   ctx, 0), true)

    check("and true", self:Evaluate({op="and", operands={
        {op="lt", field="partyHPAvg", value=0.6},
        {op="gt", field="playerMana", value=0.3},
    }}, ctx, 0), true)

    check("and false", self:Evaluate({op="and", operands={
        {op="lt", field="partyHPAvg", value=0.6},
        {op="gt", field="playerMana", value=0.9},
    }}, ctx, 0), false)

    check("or true (first)", self:Evaluate({op="or", operands={
        {op="lt", field="partyHPAvg", value=0.6},
        {op="gt", field="playerMana", value=0.9},
    }}, ctx, 0), true)

    check("or true (second)", self:Evaluate({op="or", operands={
        {op="gt", field="partyHPAvg", value=0.9},
        {op="lt", field="playerMana", value=0.9},
    }}, ctx, 0), true)

    check("or false", self:Evaluate({op="or", operands={
        {op="gt", field="partyHPAvg", value=0.9},
        {op="gt", field="playerMana", value=0.9},
    }}, ctx, 0), false)

    -- C2 회귀 방지: nil 과 true 가 공존하면 true 가 이겨야 함
    check("or nil + true = true", self:Evaluate({op="or", operands={
        {op="lt", field="tankDebuffStack", value=5},  -- 필드 미등재 → nil
        {op="lt", field="partyHPAvg", value=0.6},     -- true
    }}, ctx, 0), true)

    check("not false", self:Evaluate({op="not", operands={
        {op="lt", field="partyHPAvg", value=0.6},
    }}, ctx, 0), false)

    check("invalid op → nil",    self:Evaluate({op="exec", field="partyHPAvg", value=0.5}, ctx, 0), nil)
    check("invalid field → nil", self:Evaluate({op="lt", field="os.execute", value=0}, ctx, 0), nil)

    -- C5: not 6개 → 리프가 depth=6 에 도달 → depth > 5 초과로 nil
    local deepNode = {op="not", operands={{op="not", operands={{op="not", operands={
        {op="not", operands={{op="not", operands={{op="not", operands={
            {op="lt", field="partyHPAvg", value=0.9}
        }}}}}}
    }}}}}}
    check("depth exceeded → nil", self:Evaluate(deepNode, ctx, 0), nil)

    check("nil condition → ShouldFire true", self:ShouldFire(nil), true)

    -- spellOnCooldown: 사용 불가 op 는 nil
    check("spellOnCooldown lt → nil", self:Evaluate({op="lt", field="spellOnCooldown", spellID=12345, value=1}, ctx, 0), nil)

    -- keystoneLevel 회귀 3건 (기존)
    local ctxKs10 = { keystoneLevel = 10 }
    local ctxKs9  = { keystoneLevel = 9  }
    local ctxKs0  = { keystoneLevel = 0  }
    check("keystoneLevel gte 10 (=10) → true",  self:Evaluate({op="gte", field="keystoneLevel", value=10}, ctxKs10, 0), true)
    check("keystoneLevel gte 10 (=9)  → false", self:Evaluate({op="gte", field="keystoneLevel", value=10}, ctxKs9,  0), false)
    check("keystoneLevel gte 10 (=0)  → false", self:Evaluate({op="gte", field="keystoneLevel", value=10}, ctxKs0,  0), false)

    -- §5A 신규: dungeonKey / affixActive 3건
    local ctxM = { dungeonKey = "MaisaraCaverns", activeAffixIDs = {152, 3} }
    check("dungeonKey eq MaisaraCaverns → true",
        self:Evaluate({op="eq", field="dungeonKey", value="MaisaraCaverns"}, ctxM, 0), true)
    check("dungeonKey eq Other → false",
        self:Evaluate({op="eq", field="dungeonKey", value="Other"}, ctxM, 0), false)
    check("affixActive affixID=152 → true",
        self:Evaluate({op="eq", field="affixActive", affixID=152}, ctxM, 0), true)

    print(string.format("|cff88ff88[HG-CE]|r 자체 테스트 완료: pass=%d fail=%d", pass, fail))
end
