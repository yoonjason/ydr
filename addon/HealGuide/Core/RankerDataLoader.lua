local addonName, addon = ...
addon.RankerDataLoader = {}
local RankerDataLoader = addon.RankerDataLoader

-- ISO 8601 날짜 문자열("YYYY-MM-DD...")에서 오늘 기준 경과 일수를 반환.
-- 월을 30일 단위로 근사 계산 — 14일 초과 여부 판단에 충분한 정밀도.
local function daysSinceISO(isoStr)
    if not isoStr then return nil end
    local cy, cm, cd = isoStr:match("^(%d%d%d%d)-(%d%d)-(%d%d)")
    if not cy then return nil end
    local now = date("*t")
    local collectedDays = tonumber(cy) * 365 + tonumber(cm) * 30 + tonumber(cd)
    local todayDays = now.year * 365 + now.month * 30 + now.day
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
    local maxDays = 0
    for _, entry in ipairs(HGPT_RankerData.entries) do
        local meta = entry._meta
        if meta and meta.collectedAt then
            local days = daysSinceISO(meta.collectedAt)
            if days and days > maxDays then maxDays = days end
        end
    end
    return maxDays
end

-- (spec, encID, bossSpellID) 조합에 매칭되는 랭커 데이터 반환.
-- 매칭 없거나 useRankerData 꺼져 있으면 nil.
function RankerDataLoader:LookupBossReactions(spec, encID, bossSpellID)
    if not addon.Storage:GetSetting("useRankerData") then return nil end
    if not spec or not encID or not bossSpellID then return nil end
    if not self:IsDataAvailable() then return nil end

    for _, entry in ipairs(HGPT_RankerData.entries) do
        local meta = entry._meta
        if meta and meta.spec == spec then
            local encData = entry.data and entry.data[encID]
            if encData then
                local matched = encData[bossSpellID]
                if matched then return matched end
            end
        end
    end
    return nil
end
