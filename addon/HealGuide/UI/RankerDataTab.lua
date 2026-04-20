-- Phase 5α: 랭커 데이터 탭 UI
-- addon.MainFrame 에 _CreateRankerTab / _RefreshRankerTab 메서드를 추가.
-- TAB_RANKER = 4 상수는 MainFrame.lua 와 맞춰야 함.

local addonName, addon = ...
local MainFrame = addon.MainFrame

local ENTRY_HEADER_H = 26
local BOSS_HEADER_H  = 22
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

-- Lua 에서 0 은 truthy 이므로 GetWidth() 반환값이 0 일 때 fallback 을 쓰도록 보호
local function safeWidth(frame, fallback)
    local w = frame and frame:GetWidth()
    return (w and w > 0) and w or fallback
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

-- 보스 섹션 헤더 재사용 or 신규 생성
local function getOrCreateSectionHeader(detail, idx)
    if not detail._sectionHeaders then detail._sectionHeaders = {} end
    local h = detail._sectionHeaders[idx]
    if not h then
        h = CreateFrame("Button", nil, detail)
        h:SetHeight(BOSS_HEADER_H)
        local bg = h:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.08, 0.08, 0.25, 0.7)
        local hl = h:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.07)
        h.arrow = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        h.arrow:SetPoint("LEFT", h, "LEFT", 6, 0)
        h.label = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h.label:SetPoint("LEFT", h.arrow, "RIGHT", 4, 0)
        h.label:SetPoint("RIGHT", h, "RIGHT", -4, 0)
        h.label:SetJustifyH("LEFT")
        detail._sectionHeaders[idx] = h
    end
    return h
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
-- 보스(encID) 단위 접이식 섹션으로 계층화
local function populateDetailFrame(detail, entry)
    local data = entry.data or {}
    if not detail._sectionExpanded then detail._sectionExpanded = {} end

    for _, row in ipairs(detail._rows) do row:Hide() end
    if detail._sectionHeaders then
        for _, h in ipairs(detail._sectionHeaders) do h:Hide() end
    end

    -- 안정적인 순서를 위해 encID 정렬
    local encIDs = {}
    for encID in pairs(data) do
        if type(encID) == "number" then encIDs[#encIDs + 1] = encID end
    end
    table.sort(encIDs)

    local detailY  = -(4 + DETAIL_ROW_H)   -- colLabel 아래부터
    local rowIndex = 0
    local secIdx   = 0

    for _, encID in ipairs(encIDs) do
        local encData = data[encID]

        -- 보스 이름: _name(맥앱) > EJ > 폴백
        local bossName = addon.RankerDataLoader:GetEncounterName(encID, encData._name)

        -- 최초 접근 시 기본값 펼침
        if detail._sectionExpanded[encID] == nil then
            detail._sectionExpanded[encID] = true
        end
        local expanded = detail._sectionExpanded[encID]

        secIdx = secIdx + 1
        local sHdr = getOrCreateSectionHeader(detail, secIdx)
        sHdr:ClearAllPoints()
        sHdr:SetPoint("TOPLEFT",  detail, "TOPLEFT",  0, detailY)
        sHdr:SetPoint("TOPRIGHT", detail, "TOPRIGHT", 0, detailY)
        sHdr.arrow:SetText(expanded and "▼" or "▶")
        sHdr.label:SetText(string.format("%s (%d)", bossName, encID))
        sHdr:Show()

        local capturedEncID = encID
        sHdr:SetScript("OnClick", function()
            detail._sectionExpanded[capturedEncID] = not detail._sectionExpanded[capturedEncID]
            populateDetailFrame(detail, entry)
            addon.MainFrame:_RefreshRankerTab()
        end)

        detailY = detailY - BOSS_HEADER_H

        if expanded then
            -- bossSpellID 정렬
            local bossSpellIDs = {}
            for bssID in pairs(encData) do
                if type(bssID) == "number" then bossSpellIDs[#bossSpellIDs + 1] = bssID end
            end
            table.sort(bossSpellIDs)

            for _, bssID in ipairs(bossSpellIDs) do
                local mappings = encData[bssID]
                if type(mappings) == "table" then
                    local bossLabel = spellName(bssID)
                    local firstRow  = true
                    for _, m in ipairs(mappings) do
                        rowIndex = rowIndex + 1
                        local row = getOrCreateDetailRow(detail, rowIndex)
                        row:SetHeight(DETAIL_ROW_H)
                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT",  detail, "TOPLEFT",  0, detailY)
                        row:SetPoint("TOPRIGHT", detail, "TOPRIGHT", 0, detailY)
                        local healLabel = spellName(m.spellID or 0)
                        -- 동일 bossSpellID 의 첫 행만 보스 스킬명 표시
                        local bossCol = firstRow and bossLabel:sub(1, 21) or ""
                        row.text:SetText(string.format(
                            "%-22s %-22s %.1fs   ±%.1f   %s",
                            bossCol,
                            healLabel:sub(1, 21),
                            m.delay  or 0,
                            m.stddev or 0,
                            m.quorum or "?"
                        ))
                        row:Show()
                        detailY = detailY - DETAIL_ROW_H
                        firstRow = false
                    end
                end
            end
        end
    end

    local totalH = math.abs(detailY) + 8
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

    -- 테스트 버튼 (headerText 보다 먼저 생성해 RIGHT 앵커 기준으로 사용)
    local testBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    testBtn:SetSize(52, 20)
    testBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -math.floor((ENTRY_HEADER_H - 20) / 2))
    testBtn:SetText("테스트")
    testBtn:SetScript("OnClick", function()
        if InCombatLockdown() then
            print("|cff00ff00HealGuide|r 전투 중에는 테스트를 실행할 수 없습니다.")
            return
        end
        if addon.EncounterEngine:IsRankerTestRunning() then
            addon.EncounterEngine:CancelRankerTest()
            testBtn:SetText("테스트")
        else
            if frame._entry then
                addon.EncounterEngine.onRankerTestFinished = function()
                    testBtn:SetText("테스트")
                    addon.EncounterEngine.onRankerTestFinished = nil
                end
                addon.EncounterEngine:TestRankerEntry(frame._entry)
                testBtn:SetText("중지")
            end
        end
    end)
    testBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if addon.EncounterEngine:IsRankerTestRunning() then
            GameTooltip:SetText("테스트 중지")
            GameTooltip:AddLine("진행 중인 테스트를 중지합니다.", 1, 1, 1, true)
        else
            GameTooltip:SetText("랭커 데이터 테스트")
            GameTooltip:AddLine("이 항목의 랭커 매핑을 순서대로 시뮬레이션합니다.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    testBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.testBtn = testBtn

    -- headerBtn 이 엔트리 프레임 전체를 덮어 testBtn 영역 클릭이 headerBtn 에 먼저 소비됨.
    -- testBtn 프레임 레벨 상승 + headerBtn 우측 hit rect 축소로 클릭 우선권 부여.
    -- testBtn 크기 변경 시 자동 추종되도록 SetHitRectInsets 값을 testBtn:GetWidth() 기준으로 계산.
    testBtn:SetFrameLevel(headerBtn:GetFrameLevel() + 5)
    local hitInsetRight = testBtn:GetWidth() + 8   -- testBtn 폭 + 좌우 여백
    headerBtn:SetHitRectInsets(0, hitInsetRight, 0, 0)

    local headerText = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headerText:SetPoint("LEFT",  arrow,   "RIGHT", 4, 0)
    headerText:SetPoint("RIGHT", testBtn, "LEFT",  -4, 0)
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
    -- 풀에서 재사용된 frame 이 다른 entry 의 펼침 상태를 승계하지 않도록 entry 교체 시 초기화.
    if frame._entry ~= entry and frame.detail then
        frame.detail._sectionExpanded = nil
    end
    frame._entry = entry
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
    -- 정책 라디오 버튼 3개 (상호배타)
    local RADIO_DEFS = {
        { key = "off",       label = "데이터 사용",      x = 8,   tip = "데이터 탭(로그 분석 결과)만 사용. 랭커 데이터는 무시." },
        { key = "merge",     label = "둘 다 사용",       x = 118, tip = "랭커 매핑이 있는 보스는 랭커 데이터로, 없는 보스는 데이터 탭으로 폴백." },
        { key = "exclusive", label = "랭커 데이터 사용", x = 218, tip = "랭커 매핑이 있는 보스만 알림. 없는 보스는 알림이 뜨지 않음." },
    }

    local radios = {}
    panel._policyRadios = radios
    local firstRadio = nil

    for _, def in ipairs(RADIO_DEFS) do
        -- AlertMode 버튼과 동일 패턴: UIRadioButtonTemplate 시도 후 미지원 시 CheckButton 폴백
        local radioOk, rb = pcall(
            CreateFrame, "CheckButton", "HGPolicyRadio_" .. def.key, panel, "UIRadioButtonTemplate")
        if not radioOk then
            rb = CreateFrame("CheckButton", "HGPolicyRadio_" .. def.key, panel, "UICheckButtonTemplate")
        end
        rb:SetSize(24, 24)
        rb:SetPoint("TOPLEFT", panel, "TOPLEFT", def.x, -6)
        rb._policyKey = def.key
        _G["HGPolicyRadio_" .. def.key .. "Text"]:SetText(def.label)
        local tip = def.tip
        local label = def.label
        rb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        rb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local pkey = def.key
        rb:SetScript("OnClick", function()
            addon.Storage:SetSetting("rankerPolicy", pkey)
            for _, r in ipairs(radios) do
                r:SetChecked(r._policyKey == pkey)
            end
        end)
        radios[#radios + 1] = rb
        if not firstRadio then firstRadio = rb end
    end

    -- 데이터 새로고침 (ReloadUI)
    local reloadBtn = CreateFrame("Button", "HGRankerReloadBtn", panel, "UIPanelButtonTemplate")
    reloadBtn:SetSize(110, 22)
    reloadBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -6)
    reloadBtn:SetText("데이터 새로고침")
    reloadBtn:SetScript("OnClick", function() ReloadUI() end)
    reloadBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("데이터 새로고침")
        GameTooltip:AddLine("Mac 앱에서 저장한 최신 데이터를 반영합니다.", 1, 1, 1, true)
        GameTooltip:AddLine("UI 가 잠시 재시작됩니다.", 1, 0.8, 0.2, true)
        GameTooltip:Show()
    end)
    reloadBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.rankerReloadBtn = reloadBtn

    -- 상태 배너
    local banner = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    banner:SetPoint("TOPLEFT", firstRadio, "BOTTOMLEFT", -8, -6)
    banner:SetPoint("RIGHT",   panel,      "RIGHT",      -8,  0)
    banner:SetJustifyH("LEFT")
    banner:SetWordWrap(true)
    panel.rankerBanner = banner

    -- 스크롤 프레임
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     banner, "BOTTOMLEFT", 0,   -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel,  "BOTTOMRIGHT", -26,  4)
    panel.rankerScrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(safeWidth(scrollFrame, 490))
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

    -- 라디오 동기화
    local policy = addon.Storage:GetSetting("rankerPolicy") or "merge"
    for _, r in ipairs(panel._policyRadios) do
        r:SetChecked(r._policyKey == policy)
    end

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
    local totalWidth = safeWidth(content, 490)

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
