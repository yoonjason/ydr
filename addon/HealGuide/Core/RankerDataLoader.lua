local addonName, addon = ...
addon.RankerDataLoader = {}
local RankerDataLoader = addon.RankerDataLoader

-- 12.0 Midnight 'secret' spellID 방어: 일부 spellID 는 직접 인덱싱 시
-- 'table index is secret' 런타임 에러. pcall 로 감싸서 nil 리턴.
-- EncounterEngine 의 addon._safeIndex 와 동일 구현. 로드 순서 의존 제거 위해 자체 정의.
local function safeIndex(tbl, key)
    if not tbl or type(key) ~= "number" then return nil end
    local ok, val = pcall(function() return tbl[key] end)
    return ok and val or nil
end

-- ISO 8601 날짜 문자열("YYYY-MM-DD...")에서 오늘 기준 경과 일수를 반환.
-- 월을 30일 단위로 근사 계산 — 14일 초과 여부 판단에 충분한 정밀도.
local function daysSinceISO(isoStr, todayDays)
    if not isoStr then return nil end
    local cy, cm, cd = isoStr:match("^(%d%d%d%d)-(%d%d)-(%d%d)")
    if not cy then return nil end
    local collectedDays = tonumber(cy) * 365 + tonumber(cm) * 30 + tonumber(cd)
    return math.max(0, todayDays - collectedDays)
end

-- HGPT_RankerData 전역이 존재하고 entries 배열이 비어있지 않으면 true.
function RankerDataLoader:IsDataAvailable()
    return type(HGPT_RankerData) == "table"
        and type(HGPT_RankerData.entries) == "table"
        and #HGPT_RankerData.entries > 0
end

-- 모든 entries 반환. 데이터 없으면 빈 테이블.
function RankerDataLoader:GetEntries()
    if not self:IsDataAvailable() then return {} end
    return HGPT_RankerData.entries
end

-- 전체 entries 중 가장 오래된 collectedAt 기준 경과 일수 반환.
-- 데이터 없으면 nil.
function RankerDataLoader:GetMaxDaysSinceCollection()
    if not self:IsDataAvailable() then return nil end
    local now = date("*t")
    local todayDays = now.year * 365 + now.month * 30 + now.day
    local maxDays = 0
    for _, entry in ipairs(HGPT_RankerData.entries) do
        local meta = entry._meta
        if meta and meta.collectedAt then
            local days = daysSinceISO(meta.collectedAt, todayDays)
            if days and days > maxDays then maxDays = days end
        end
    end
    return maxDays
end

-- (spec, encID, bossSpellID) 조합에 매칭되는 랭커 데이터 반환.
-- 호출부(EncounterEngine / Bridge / TestRankerEntry)가 이미 rankerPolicy 를 확인하고
-- 진입하므로 여기서는 정책 체크를 생략 — OnCombatLog 핫패스에서 매 캐스트마다
-- GetSetting 호출하는 비용 제거.
function RankerDataLoader:LookupBossReactions(spec, encID, bossSpellID)
    if not spec or not encID or not bossSpellID then return nil end
    if type(bossSpellID) ~= "number" then return nil end
    if not self:IsDataAvailable() then return nil end

    for _, entry in ipairs(HGPT_RankerData.entries) do
        local meta = entry._meta
        if meta and meta.spec == spec then
            -- entry.data[encID] 접근도 safeIndex 로 방어 (encID 는 보통 정수지만 혹시 모를 secret ID 대비)
            local encData = entry.data and safeIndex(entry.data, encID)
            if encData then
                local matched = safeIndex(encData, bossSpellID)
                if matched then return matched end
            end
        end
    end
    return nil
end

function RankerDataLoader:HasEncounterData(spec, encID)
    if not spec or not encID then return false end
    if not self:IsDataAvailable() then return false end
    for _, entry in ipairs(HGPT_RankerData.entries) do
        local meta = entry._meta
        if meta and meta.spec == spec then
            if entry.data and safeIndex(entry.data, encID) then return true end
        end
    end
    return false
end

function RankerDataLoader:CountEntries(spec, encID)
    if not spec or not encID then return 0 end
    if not self:IsDataAvailable() then return 0 end
    local count = 0
    for _, entry in ipairs(HGPT_RankerData.entries) do
        local meta = entry._meta
        if meta and meta.spec == spec then
            local encData = entry.data and safeIndex(entry.data, encID)
            if encData then
                -- _name 등 문자열 메타 키 제외, 정수 bossSpellID 만 카운트
                for k in pairs(encData) do
                    if type(k) == "number" then count = count + 1 end
                end
            end
        end
    end
    return count
end

-- 2단 fallback: _bossNames 맵을 역조회해 이름이 일치하는 bossSpellID 의 reactions 반환.
-- 맥앱이 data[encID]._bossNames[bossSpellID] = '이름' 포맷으로 저장한다고 가정.
-- _bossNames 없으면 nil 반환 (역호환).
function RankerDataLoader:LookupByBossSpellName(spec, encID, bossSpellName)
    if not spec or not encID or not bossSpellName then return nil end
    if not self:IsDataAvailable() then return nil end

    for _, entry in ipairs(HGPT_RankerData.entries) do
        local meta = entry._meta
        if meta and meta.spec == spec then
            local encData = entry.data and safeIndex(entry.data, encID)
            if encData then
                local bossNames = encData._bossNames  -- string key: safeIndex 불필요
                if type(bossNames) == "table" then
                    for bossSpellID, name in pairs(bossNames) do
                        if name == bossSpellName then
                            local matched = safeIndex(encData, bossSpellID)
                            if matched then return matched end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- 3단 fallback: (spec, encID) 전체 reactions 를 평탄화해 빈도 높은 상위 3개 반환.
-- 리턴: { { spellID, score, delay=0, category='fallback' }, ... } 또는 nil.
-- 호출부(EncounterEngine)에서 쿨다운 필터 후 첫 번째 후보를 사용한다.
function RankerDataLoader:LookupEncounterFallbackReaction(spec, encID)
    if not spec or not encID then return nil end
    if not self:IsDataAvailable() then return nil end

    local scores = {}  -- spellID → 가중 점수 (count × quorum_비율)

    for _, entry in ipairs(HGPT_RankerData.entries) do
        local meta = entry._meta
        if meta and meta.spec == spec then
            local encData = entry.data and safeIndex(entry.data, encID)
            if encData then
                for bossSpellID in pairs(encData) do
                    if type(bossSpellID) == "number" then
                        local reactions = safeIndex(encData, bossSpellID)
                        if type(reactions) == "table" then
                            for _, r in ipairs(reactions) do
                                local sid = r.spellID
                                if type(sid) == "number" then
                                    local cnt = tonumber(r.count) or 1
                                    local quorumFrac = 1.0
                                    if type(r.quorum) == "string" then
                                        local num, den = r.quorum:match("(%d+)/(%d+)")
                                        if num and den and tonumber(den) > 0 then
                                            quorumFrac = tonumber(num) / tonumber(den)
                                        end
                                    end
                                    scores[sid] = (scores[sid] or 0) + cnt * quorumFrac
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if not next(scores) then return nil end

    local sorted = {}
    for sid, score in pairs(scores) do
        sorted[#sorted + 1] = { spellID = sid, score = score, delay = 0, category = "fallback" }
    end
    table.sort(sorted, function(a, b) return a.score > b.score end)

    local result = {}
    for i = 1, math.min(3, #sorted) do
        result[i] = sorted[i]
    end
    return result
end

-- encID → 보스 이름 캐시 (세션 내 유지)
local encNameCache = {}

-- 보스 이름 해상: optionalName(맥앱 _name) > EJ_GetEncounterInfo > 폴백
function RankerDataLoader:GetEncounterName(encID, optionalName)
    if optionalName and optionalName ~= "" then
        encNameCache[encID] = optionalName
        return optionalName
    end
    if encNameCache[encID] then return encNameCache[encID] end
    if EJ_GetEncounterInfo then
        local ok, name = pcall(EJ_GetEncounterInfo, encID)
        if ok and type(name) == "string" and name ~= "" then
            encNameCache[encID] = name
            return name
        end
    end
    local fallback = "Enc " .. tostring(encID)
    encNameCache[encID] = fallback
    return fallback
end
