-- Phase 5α: 랭커 데이터 탭 UI
-- addon.MainFrame 에 _CreateRankerTab / _RefreshRankerTab 메서드를 추가.
-- TAB_RANKER = 4 상수는 MainFrame.lua 와 맞춰야 함.

local addonName, addon = ...
local MainFrame = addon.MainFrame

local ENTRY_HEADER_H = 26
local DETAIL_ROW_H   = 18
local STALE_DAYS     = 14

-- 스펠 ID → 이름 변환 (런타임 조회, 실패 시 ID 문자열 반환)
local function spellName(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    return "ID:" .. tostring(spellID)
end

-- ── 상세 펼치기 프레임 생성 ────────────────────────────────────────────────────

local function createDetailFrame(parent)
    local detail = CreateFrame("Frame", nil, parent)
    detail._rows = {}

    local colLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colLabel:SetPoint("TOPLEFT", detail, "TOPLEFT", 8, -4)
    colLabel:SetText("|cffaaaaaa보스 스킬                힐 스킬                delay   ±stddev   quorum|r")
    detail.colLabel = colLabel

    return detail
end

-- 상세 행 재사용 or 신규 생성
local function getOrCreateDetailRow(detail, index)
    local row = detail._rows[index]
    if not row then
        row = CreateFrame("Frame", nil, detail)
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT",  row, "LEFT",  8, 0)
        text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        text:SetJustifyH("LEFT")
        row.text = text
        detail._rows[index] = row
    end
    return row
end

-- 엔트리 데이터로 상세 프레임 내용 갱신, 상세 프레임 총 높이 반환
local function populateDetailFrame(detail, entry)
    local data = entry.data or {}
    local rowIndex = 0
    local detailY = -(4 + DETAIL_ROW_H)   -- colLabel 아래부터

    -- 기존 행 숨기기
    for _, row in ipairs(detail._rows) do row:Hide() end

    for encID, encData in pairs(data) do
        for bossSpellID, mappings in pairs(encData) do
            local bossLabel = spellName(bossSpellID)
            for _, m in ipairs(mappings) do
                rowIndex = rowIndex + 1
                local row = getOrCreateDetailRow(detail, rowIndex)
                row:SetHeight(DETAIL_ROW_H)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",  detail, "TOPLEFT",  0, detailY)
                row:SetPoint("TOPRIGHT", detail, "TOPRIGHT", 0, detailY)
                local healLabel = spellName(m.spellID or 0)
                row.text:SetText(string.format(
                    "%-22s %-22s %.1fs   ±%.1f   %s",
                    bossLabel:sub(1, 21),
                    healLabel:sub(1, 21),
                    m.delay  or 0,
                    m.stddev or 0,
                    m.quorum or "?"
                ))
                row:Show()
                detailY = detailY - DETAIL_ROW_H
            end
        end
    end

    local totalH = 4 + DETAIL_ROW_H + math.max(1, rowIndex) * DETAIL_ROW_H + 4
    detail:SetHeight(totalH)
    return totalH
end

-- ── 엔트리 프레임 생성 ───────────────────────────────────────────────────────

local function createEntryFrame(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame._expanded = false

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.5)

    -- 헤더 버튼 (클릭으로 확장/축소)
    local headerBtn = CreateFrame("Button", nil, frame)
    headerBtn:SetHeight(ENTRY_HEADER_H)
    headerBtn:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    headerBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local hl = headerBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    local arrow = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("LEFT", headerBtn, "LEFT", 4, 0)
    arrow:SetText("▶")
    frame.arrow = arrow

    local headerText = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headerText:SetPoint("LEFT",  arrow,     "RIGHT", 4, 0)
    headerText:SetPoint("RIGHT", headerBtn, "RIGHT", -4, 0)
    headerText:SetJustifyH("LEFT")
    headerText:SetWordWrap(false)
    frame.headerText = headerText

    -- 상세 프레임
    local detail = createDetailFrame(frame)
    detail:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, -ENTRY_HEADER_H)
    detail:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -ENTRY_HEADER_H)
    detail:Hide()
    frame.detail = detail

    headerBtn:SetScript("OnClick", function()
        frame._expanded = not frame._expanded
        frame.arrow:SetText(frame._expanded and "▼" or "▶")
        if frame._expanded then
            frame.detail:Show()
        else
            frame.detail:Hide()
        end
        -- 스크롤 컨텐츠 높이 재계산
        addon.MainFrame:_RefreshRankerTab()
    end)

    return frame
end

-- 엔트리 프레임에 데이터 적용, 프레임 총 높이 반환
local function updateEntryFrame(frame, entry, totalWidth)
    local meta = entry._meta or {}

    local dateStr    = meta.collectedAt and meta.collectedAt:sub(1, 10) or "?"
    local rankersStr = tostring(meta.rankersUsed or "?") .. "/" .. tostring(meta.rankersRequested or "?")
    frame.headerText:SetText(string.format(
        "%s  ·  %s  ·  %s  ·  %s  ·  랭커 %s",
        meta.spec        or "?",
        meta.dungeonName or "?",
        meta.difficulty  or "?",
        dateStr,
        rankersStr
    ))

    local detailH = 0
    if frame._expanded then
        detailH = populateDetailFrame(frame.detail, entry)
    end

    local totalH = ENTRY_HEADER_H + (frame._expanded and detailH or 0)
    frame:SetSize(totalWidth, totalH)
    return totalH
end

-- ── MainFrame 메서드 ─────────────────────────────────────────────────────────

function MainFrame:_CreateRankerTab(panel)
    -- 전체 토글
    local toggleCB = CreateFrame("CheckButton", "HGRankerToggleCB", panel, "UICheckButtonTemplate")
    toggleCB:SetSize(24, 24)
    toggleCB:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
    _G["HGRankerToggleCBText"]:SetText("랭커 데이터 적용")
    toggleCB:SetScript("OnClick", function(self)
        addon.Storage:SetSetting("useRankerData", self:GetChecked() and true or false)
    end)
    panel.rankerToggleCB = toggleCB

    -- 상태 배너
    local banner = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    banner:SetPoint("TOPLEFT", toggleCB, "BOTTOMLEFT", -8, -6)
    banner:SetPoint("RIGHT",   panel,    "RIGHT",      -8,  0)
    banner:SetJustifyH("LEFT")
    banner:SetWordWrap(true)
    panel.rankerBanner = banner

    -- 스크롤 프레임
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     banner, "BOTTOMLEFT", 0,   -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel,  "BOTTOMRIGHT", -26,  4)
    panel.rankerScrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth() or 490)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    panel.rankerContent  = content
    panel._rankerEntryFrames = {}

    -- 패널 참조 저장 (RankerDataTab 전용)
    addon.MainFrame._rankerPanel = panel
end

function MainFrame:_RefreshRankerTab()
    local panel = addon.MainFrame._rankerPanel
    if not panel then return end

    -- 토글 동기화
    local useRanker = addon.Storage:GetSetting("useRankerData")
    if useRanker == nil then useRanker = true end
    panel.rankerToggleCB:SetChecked(useRanker and true or false)

    -- 배너
    local loader = addon.RankerDataLoader
    if not loader or not loader:IsDataAvailable() then
        panel.rankerBanner:SetText("|cffff8888데이터 없음 — Mac 앱에서 수집하세요|r")
    else
        local maxDays = loader:GetMaxDaysSinceCollection()
        if maxDays and maxDays > STALE_DAYS then
            panel.rankerBanner:SetText(string.format(
                "|cffffff00%d일 경과 — 갱신 권장 (Mac 앱에서 재수집하세요)|r", maxDays))
        else
            panel.rankerBanner:SetText("|cff88ff88데이터 최신 상태|r")
        end
    end

    -- 엔트리 목록 재구성
    local content    = panel.rankerContent
    local entryFrames = panel._rankerEntryFrames
    local totalWidth = content:GetWidth() or 490

    for _, ef in ipairs(entryFrames) do ef:Hide() end

    if not loader or not loader:IsDataAvailable() then
        content:SetHeight(40)
        return
    end

    local entries = loader:GetEntries()
    local yOffset = -4
    local frameIndex = 0

    for _, entry in ipairs(entries) do
        if type(entry) == "table" and entry._meta then
            frameIndex = frameIndex + 1
            local entryFrame = entryFrames[frameIndex]
            if not entryFrame then
                entryFrame = createEntryFrame(content)
                entryFrames[frameIndex] = entryFrame
            end
            local entryH = updateEntryFrame(entryFrame, entry, totalWidth)
            entryFrame:ClearAllPoints()
            entryFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
            entryFrame:Show()
            yOffset = yOffset - entryH - 2
        end
    end

    content:SetHeight(math.abs(yOffset) + 8)
end
