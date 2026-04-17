local addonName, addon = ...
addon.MainFrame = {}
local MainFrame = addon.MainFrame

local mainFrame    = nil
local tabs         = {}
local activeTab    = 1

local TAB_DATA     = 1
local TAB_SETTINGS = 2
local TAB_PREVIEW  = 3

-- ── Public API ───────────────────────────────────────────────────────────────

function MainFrame:Init()
    self:_Create()
end

function MainFrame:Toggle()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        self:_ShowTab(activeTab)
        mainFrame:Show()
    end
    -- 편집 모드 토글은 OnShow/OnHide 훅이 자동 처리
end

function MainFrame:Refresh()
    if not mainFrame then return end
    self:_RefreshDataTab()
end

function MainFrame:UpdateCoordLabel(x, y)
    local st = tabs[TAB_SETTINGS]
    if st and st.coordLabel then
        st.coordLabel:SetText(string.format("위치: %.0f, %.0f", x, y))
    end
end

-- ── Tab management ───────────────────────────────────────────────────────────

function MainFrame:_ShowTab(idx)
    activeTab = idx
    for i, panel in ipairs(tabs) do
        if i == idx then
            panel:Show()
            panel.tabBtn:LockHighlight()
        else
            panel:Hide()
            panel.tabBtn:UnlockHighlight()
        end
    end
    if idx == TAB_DATA then
        self:_RefreshDataTab()
    elseif idx == TAB_SETTINGS then
        self:_RefreshSettings()
    end
end

-- ── Frame creation ───────────────────────────────────────────────────────────

function MainFrame:_Create()
    mainFrame = CreateFrame("Frame", "HealGuideMainFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(560, 520)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop",  mainFrame.StopMovingOrSizing)
    -- 닫기 버튼(X) / ESC 경로에서도 편집 모드 해제되도록 OnHide 훅
    mainFrame:SetScript("OnShow", function()
        if addon.AlertFrame and addon.AlertFrame.EnterEditMode then
            addon.AlertFrame:EnterEditMode()
        end
    end)
    mainFrame:SetScript("OnHide", function()
        if addon.AlertFrame and addon.AlertFrame.ExitEditMode then
            addon.AlertFrame:ExitEditMode()
        end
    end)
    mainFrame:Hide()

    mainFrame.TitleText:SetText("HealGuide")
    mainFrame._dungeonBlocks = {}

    self:_CreateStaticPopups()

    local inset    = mainFrame.InsetBg
    local tabNames = { "데이터", "설정", "미리보기" }
    local tabBtns  = {}

    for i, name in ipairs(tabNames) do
        local btn = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
        btn:SetSize(94, 22)
        if i == 1 then
            btn:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
        else
            btn:SetPoint("LEFT", tabBtns[i - 1], "RIGHT", 2, 0)
        end
        btn:SetText(name)
        tabBtns[i] = btn

        local panel = CreateFrame("Frame", nil, mainFrame)
        panel:SetPoint("TOPLEFT",     inset, "TOPLEFT",     4, -30)
        panel:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4,  4)
        panel:Hide()
        panel.tabBtn = btn
        tabs[i] = panel

        local idx = i
        btn:SetScript("OnClick", function() MainFrame:_ShowTab(idx) end)
    end

    self:_CreateDataTab(tabs[TAB_DATA])
    self:_CreateSettingsTab(tabs[TAB_SETTINGS])
    self:_CreatePreviewTab(tabs[TAB_PREVIEW])
    self:_ShowTab(TAB_DATA)
end

function MainFrame:_CreateStaticPopups()
    StaticPopupDialogs["HEALGUIDE_CONFIRM_DELETE"] = {
        text          = "던전을 삭제하시겠습니까?",
        button1       = "삭제",
        button2       = "취소",
        OnAccept      = function(self)
            local key = self.data and self.data.dungeonKey
            if key then
                addon.Storage:RemoveDungeon(key)
                MainFrame:Refresh()
            end
        end,
        timeout        = 0,
        whileDead      = true,
        hideOnEscape   = true,
        preferredIndex = 3,
    }

    StaticPopupDialogs["HEALGUIDE_RENAME"] = {
        text       = "새 이름을 입력하세요:",
        button1    = "확인",
        button2    = "취소",
        hasEditBox = true,
        OnShow     = function(self)
            local eb = self.EditBox or self.editBox
            eb:SetText(self.data and self.data.currentName or "")
            eb:HighlightText()
        end,
        OnAccept   = function(self)
            local eb = self.EditBox or self.editBox
            local newName = eb:GetText():match("^%s*(.-)%s*$")
            local key     = self.data and self.data.dungeonKey
            if newName ~= "" and key then
                addon.Storage:SetDungeonDisplayName(key, newName)
                MainFrame:Refresh()
            end
        end,
        timeout        = 0,
        whileDead      = true,
        hideOnEscape   = true,
        preferredIndex = 3,
    }
end

-- ── Tab 1: 데이터 ─────────────────────────────────────────────────────────────

function MainFrame:_CreateDataTab(panel)
    local headerText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    headerText:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
    panel.headerText = headerText

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     headerText, "BOTTOMLEFT", 0,   -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel,      "BOTTOMRIGHT", -26, 34)
    panel.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth() or 490)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    panel.content = content

    local importBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    importBtn:SetSize(140, 22)
    importBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 4, 4)
    importBtn:SetText("+ 새 던전 import")
    importBtn:SetScript("OnClick", function()
        addon.ImportDialog:Open()
    end)

    local pauseBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    pauseBtn:SetSize(80, 22)
    pauseBtn:SetPoint("LEFT", importBtn, "RIGHT", 4, 0)
    pauseBtn:SetText("일시중지")
    pauseBtn:SetScript("OnClick", function()
        if addon.EncounterEngine.paused then
            addon.EncounterEngine:Resume()
        else
            addon.EncounterEngine:Pause()
        end
        pauseBtn:SetText(addon.EncounterEngine.paused and "재개" or "일시중지")
    end)
    panel.pauseBtn = pauseBtn

    local historyBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    historyBtn:SetSize(80, 22)
    historyBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 4, 0)
    historyBtn:SetText("전투 기록")
    historyBtn:SetScript("OnClick", function()
        if addon.CombatHistoryFrame then
            addon.CombatHistoryFrame:Toggle()
        end
    end)
end

function MainFrame:_RefreshDataTab()
    local panel = tabs[TAB_DATA]
    if not panel then return end

    if panel.pauseBtn and addon.EncounterEngine then
        panel.pauseBtn:SetText(addon.EncounterEngine.paused and "재개" or "일시중지")
    end

    local spec     = addon.SpecMatcher:GetActiveSpec() or "비힐러"
    local charName = UnitName("player") or "?"
    panel.headerText:SetText(charName .. "  —  " .. spec)

    local dungeons   = addon.Storage:GetDungeons()
    local sortedKeys = {}
    for k in pairs(dungeons) do
        table.insert(sortedKeys, k)
    end
    table.sort(sortedKeys, function(a, b)
        return (dungeons[a].importedAt or 0) < (dungeons[b].importedAt or 0)
    end)

    local content    = panel.content
    local blocks     = mainFrame._dungeonBlocks
    local totalWidth = content:GetWidth() or 490
    local usedKeys   = {}
    local yOffset    = -4

    for _, dungeonKey in ipairs(sortedKeys) do
        usedKeys[dungeonKey] = true
        local dungeon = dungeons[dungeonKey]

        local block = blocks[dungeonKey]
        if not block then
            block = self:_CreateDungeonBlockFrame(content)
            blocks[dungeonKey] = block
        end

        local rowH = self:_UpdateDungeonBlock(block, dungeonKey, dungeon, totalWidth)
        block:ClearAllPoints()
        block:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
        block:Show()
        yOffset = yOffset - rowH - 4
    end

    -- 삭제된 던전 블록 숨기기 (B3: 프레임 풀, GC 대상 아님)
    for key, block in pairs(blocks) do
        if not usedKeys[key] then
            block:Hide()
        end
    end

    content:SetHeight(math.abs(yOffset) + 10)
end

function MainFrame:_CreateDungeonBlockFrame(parent)
    local block = CreateFrame("Frame", nil, parent)
    block._bossRows = {}

    local bg = block:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.5)

    local toggleBtn = CreateFrame("Button", nil, block, "GameMenuButtonTemplate")
    toggleBtn:SetSize(40, 20)
    toggleBtn:SetPoint("TOPLEFT", block, "TOPLEFT", 4, -4)
    block.toggleBtn = toggleBtn

    local nameText = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT",  toggleBtn, "RIGHT", 6, 0)
    nameText:SetPoint("RIGHT", block,     "RIGHT", 160, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    block.nameText = nameText

    local renameBtn = CreateFrame("Button", nil, block, "GameMenuButtonTemplate")
    renameBtn:SetSize(66, 20)
    renameBtn:SetPoint("TOPRIGHT", block, "TOPRIGHT", -112, -4)
    renameBtn:SetText("이름변경")
    block.renameBtn = renameBtn

    local refreshBtn = CreateFrame("Button", nil, block, "GameMenuButtonTemplate")
    refreshBtn:SetSize(40, 20)
    refreshBtn:SetPoint("LEFT", renameBtn, "RIGHT", 2, 0)
    refreshBtn:SetText("갱신")
    block.refreshBtn = refreshBtn

    local deleteBtn = CreateFrame("Button", nil, block, "GameMenuButtonTemplate")
    deleteBtn:SetSize(40, 20)
    deleteBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 2, 0)
    deleteBtn:SetText("|cffff4444삭제|r")
    block.deleteBtn = deleteBtn

    return block
end

function MainFrame:_UpdateDungeonBlock(block, dungeonKey, dungeon, totalWidth)
    local HEADER_H = 28
    local BOSS_H   = 20

    local bossCount = 0
    for _ in pairs(dungeon.bosses) do bossCount = bossCount + 1 end

    local totalH = HEADER_H + bossCount * BOSS_H
    block:SetSize(totalWidth, totalH)

    block.toggleBtn:SetText(dungeon.enabled and "|cff00ff00ON|r" or "|cffff4444OFF|r")
    block.toggleBtn:SetScript("OnClick", function()
        addon.Storage:SetDungeonEnabled(dungeonKey, not dungeon.enabled)
        MainFrame:Refresh()
    end)

    local label = dungeon.displayName
    if dungeon.originalName ~= dungeon.displayName then
        label = label .. " |cff888888(" .. dungeon.originalName .. ")|r"
    end
    block.nameText:SetText(label)

    block.renameBtn:SetScript("OnClick", function()
        StaticPopup_Show("HEALGUIDE_RENAME", nil, nil,
            { dungeonKey = dungeonKey, currentName = dungeon.displayName })
    end)

    block.refreshBtn:SetScript("OnClick", function()
        addon.ImportDialog:Open(dungeonKey)
    end)

    block.deleteBtn:SetScript("OnClick", function()
        StaticPopup_Show("HEALGUIDE_CONFIRM_DELETE", nil, nil, { dungeonKey = dungeonKey })
    end)

    for _, row in ipairs(block._bossRows) do
        row:Hide()
    end

    local rowIdx = 0
    local bossY  = -HEADER_H
    for encounterID, boss in pairs(dungeon.bosses) do
        rowIdx = rowIdx + 1
        local bossRow = block._bossRows[rowIdx]
        if not bossRow then
            bossRow = CreateFrame("Frame", nil, block)
            bossRow:SetHeight(BOSS_H)
            local bossText = bossRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            bossText:SetPoint("LEFT", bossRow, "LEFT", 0, 0)
            bossRow.bossText = bossText
            block._bossRows[rowIdx] = bossRow
        end

        bossRow:SetWidth(totalWidth - 20)
        bossRow:ClearAllPoints()
        bossRow:SetPoint("TOPLEFT", block, "TOPLEFT", 20, bossY)
        bossRow:Show()

        local specList = {}
        if boss.specs then
            for s in pairs(boss.specs) do table.insert(specList, s) end
            table.sort(specList)
        end
        local specStr = #specList > 0
            and (" |cff888888[" .. table.concat(specList, ", ") .. "]|r") or ""
        bossRow.bossText:SetText(
            "|cffaaaaaa" .. (boss.name or "?") .. "|r  " .. encounterID .. specStr)

        bossY = bossY - BOSS_H
    end

    return totalH
end

-- ── Tab 2: 설정 ───────────────────────────────────────────────────────────────

function MainFrame:_CreateSettingsTab(panel)
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     panel, "TOPLEFT",     0,  0)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 0)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth() or 460)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    panel.content = content

    local y = -8
    y = self:_CreateSettings_AlertPosition(panel, content, y)
    y = self:_CreateSettings_Timeline(panel, content, y)
    y = self:_CreateSettings_MPlus(panel, content, y)
    y = self:_CreateSettings_AlertSize(panel, content, y)
    y = self:_CreateSettings_LeadTime(panel, content, y)
    y = self:_CreateSettings_AlertDisplay(panel, content, y)

    local ttsGroup = CreateFrame("Frame", nil, content)
    ttsGroup:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    ttsGroup:SetPoint("RIGHT",   content, "RIGHT",   0, 0)
    panel.ttsGroup = ttsGroup
    local ttsGroupH = self:_CreateSettings_TTS(panel, ttsGroup)
    ttsGroup:SetHeight(ttsGroupH)
    panel._ttsGroupH = ttsGroupH

    local afterTts = CreateFrame("Frame", nil, content)
    afterTts:SetPoint("TOPLEFT", ttsGroup, "BOTTOMLEFT", 0, -4)
    afterTts:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    local ay = 0
    ay = self:_CreateSettings_AlertMode(panel, afterTts, ay)
    ay = self:_CreateSettings_Sound(panel, afterTts, ay)
    ay = self:_CreateSettings_Condition(panel, afterTts, ay)
    ay = self:_CreateSettings_Developer(panel, afterTts, ay)
    afterTts:SetHeight(math.abs(ay) + 16)
    content:SetHeight(math.abs(y) + ttsGroupH + 4 + math.abs(ay) + 16)
end

function MainFrame:_CreateSettings_AlertPosition(panel, content, y)
    self:_MakeSectionLabel(content, "알림 위치", 8, y)
    y = y - 22

    local lockCB = self:_MakeCheckbox("HGTabLockCB", "알림창 잠금", content, 8, y)
    lockCB:SetScript("OnClick", function(self)
        addon.Storage:SetSetting("locked", self:GetChecked() and true or false)
    end)
    panel.lockCB = lockCB

    local resetBtn = CreateFrame("Button", nil, content, "GameMenuButtonTemplate")
    resetBtn:SetSize(88, 20)
    resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 150, y - 2)
    resetBtn:SetText("위치 초기화")
    resetBtn:SetScript("OnClick", function()
        addon.AlertFrame:ResetPosition()
    end)

    local coordLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coordLabel:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
    coordLabel:SetText("위치: 0, 200")
    panel.coordLabel = coordLabel

    y = y - 32
    return y
end

function MainFrame:_CreateSettings_Timeline(panel, content, y)
    self:_MakeSectionLabel(content, "타임라인", 8, y)
    y = y - 22

    local tlVisibleCB = self:_MakeCheckbox("HGTabTLVisibleCB", "타임라인 표시", content, 8, y)
    tlVisibleCB:SetScript("OnClick", function(self)
        addon.Storage:SetSetting("timelineVisible", self:GetChecked() and true or false)
        addon.TimelineFrame:ApplyVisibility()
    end)
    panel.tlVisibleCB = tlVisibleCB

    local tlLockCB = self:_MakeCheckbox("HGTabTLLockCB", "타임라인 잠금", content, 150, y)
    tlLockCB:SetScript("OnClick", function(self)
        addon.Storage:SetSetting("timelineLocked", self:GetChecked() and true or false)
    end)
    panel.tlLockCB = tlLockCB

    local tlResetBtn = CreateFrame("Button", nil, content, "GameMenuButtonTemplate")
    tlResetBtn:SetSize(88, 20)
    tlResetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 300, y - 2)
    tlResetBtn:SetText("위치 초기화")
    tlResetBtn:SetScript("OnClick", function()
        addon.TimelineFrame:ResetPosition()
    end)
    y = y - 32

    self:_MakeSectionLabel(content, "방향", 8, y)
    y = y - 22

    panel.tlOrientBtns = {}
    local TL_ORIENTS = { { mode = "horizontal", label = "가로" }, { mode = "vertical", label = "세로" } }
    local tlOxs = { 8, 100 }
    for i, entry in ipairs(TL_ORIENTS) do
        local ok, btn = pcall(CreateFrame, "CheckButton", "HGTabTLOrient" .. i, content, "UIRadioButtonTemplate")
        if not ok then
            btn = CreateFrame("CheckButton", "HGTabTLOrient" .. i, content, "UICheckButtonTemplate")
        end
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", tlOxs[i], y + 4)
        btn._orient = entry.mode
        _G["HGTabTLOrient" .. i .. "Text"]:SetText(entry.label)
        btn:SetScript("OnClick", function(self)
            if panel and panel._refreshing then return end
            addon.Storage:SetSetting("timelineOrientation", self._orient)
            for _, other in ipairs(panel.tlOrientBtns) do
                other:SetChecked(other._orient == self._orient)
            end
            addon.TimelineFrame:ApplyLayout()
        end)
        panel.tlOrientBtns[i] = btn
    end
    y = y - 30

    local TL_WINDOW_PRESETS = { { label = "5s", val = 5 }, { label = "10s", val = 10 }, { label = "15s", val = 15 } }
    local TL_PRESET_NAMES   = { "HGTabTLPreset5", "HGTabTLPreset10", "HGTabTLPreset15" }
    for i, preset in ipairs(TL_WINDOW_PRESETS) do
        local pb = CreateFrame("Button", TL_PRESET_NAMES[i], content, "GameMenuButtonTemplate")
        pb:SetSize(36, 20)
        pb:SetPoint("TOPLEFT", content, "TOPLEFT", 8 + (i - 1) * 40, y - 2)
        pb:SetText(preset.label)
        local v = preset.val
        pb:SetScript("OnClick", function()
            -- 슬라이더 동기화 중 OnValueChanged 의 중복 저장 방지
            panel._refreshing = true
            addon.Storage:SetSetting("timelineWindow", v)
            panel.tlWindowSl:SetValue(v)
            panel._refreshing = false
            addon.TimelineFrame:ApplyLayout()
        end)
    end
    y = y - 28

    local tlWindowSl = self:_MakeSlider("HGTabTLWindowSl", "표시 창(초)", 10, 60, 1, content, y)
    tlWindowSl:SetScript("OnValueChanged", function(self, val)
        if panel and panel._refreshing then return end
        val = math.floor(val)
        _G[self:GetName() .. "Text"]:SetText(self._labelText .. ": " .. val)
        addon.Storage:SetSetting("timelineWindow", val)
        addon.TimelineFrame:ApplyLayout()
    end)
    panel.tlWindowSl = tlWindowSl
    y = y - 50

    local tlIconSl = self:_MakeSlider("HGTabTLIconSl", "아이콘 크기", 24, 64, 1, content, y)
    tlIconSl:SetScript("OnValueChanged", function(self, val)
        if panel and panel._refreshing then return end
        val = math.floor(val)
        _G[self:GetName() .. "Text"]:SetText(self._labelText .. ": " .. val)
        addon.Storage:SetSetting("timelineIconSize", val)
        addon.TimelineFrame:ApplyLayout()
    end)
    panel.tlIconSl = tlIconSl
    y = y - 50

    local tlTrackSl = self:_MakeSlider("HGTabTLTrackSl", "트랙 길이", 200, 800, 10, content, y)
    tlTrackSl:SetScript("OnValueChanged", function(self, val)
        if panel and panel._refreshing then return end
        val = math.floor(val / 10) * 10
        _G[self:GetName() .. "Text"]:SetText(self._labelText .. ": " .. val)
        addon.Storage:SetSetting("timelineTrackLength", val)
        addon.TimelineFrame:ApplyLayout()
    end)
    panel.tlTrackSl = tlTrackSl
    y = y - 50

    local tlTickCB = self:_MakeCheckbox("HGTabTLTickCB", "5초 마커 표시", content, 8, y)
    tlTickCB:SetScript("OnClick", function(self)
        addon.Storage:SetSetting("timelineShowTicks", self:GetChecked() and true or false)
    end)
    panel.tlTickCB = tlTickCB
    y = y - 32

    return y
end

function MainFrame:_CreateSettings_MPlus(panel, content, y)
    self:_MakeSectionLabel(content, "쐐기돌", 8, y)
    y = y - 22

    local ksMinSl = self:_MakeSlider("HGTabKsMinSl", "알림 레벨 하한", 2, 20, 1, content, y)
    ksMinSl:SetScript("OnValueChanged", function(self, val)
        if panel and panel._refreshing then return end
        val = math.floor(val)
        _G[self:GetName() .. "Text"]:SetText(self._labelText .. ": +" .. val)
        addon.Storage:SetSetting("keystoneMinLevel", val)
    end)
    panel.ksMinSl = ksMinSl
    y = y - 50

    -- §5D: 현재 키스톤 레벨 표시 — Core 가 EncounterEngine.keystoneLevel 을 업데이트
    local ksLevelLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ksLevelLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
    ksLevelLabel:SetText("현재 키: 비 쐐기")
    panel.ksLevelLabel = ksLevelLabel
    y = y - 22

    return y
end

function MainFrame:_CreateSettings_AlertSize(panel, content, y)
    self:_MakeSectionLabel(content, "알림 크기 (펄스)", 8, y)
    y = y - 22

    local baseSl = self:_MakeSlider("HGTabBaseSl", "기본 크기", 32, 128, 1, content, y)
    panel.baseSl = baseSl
    y = y - 50

    local pulseSl = self:_MakeSlider("HGTabPulseSl", "확대 크기", 48, 160, 1, content, y)
    panel.pulseSl = pulseSl
    y = y - 50

    baseSl:SetScript("OnValueChanged", function(self, val)
        if panel and panel._refreshing then return end
        val = math.floor(val)
        _G[self:GetName() .. "Text"]:SetText(self._labelText .. ": " .. val)
        addon.Storage:SetSetting("iconBaseSize", val)
        local pulse = addon.Storage:GetSetting("iconPulseSize") or 96
        if pulse < val then
            addon.Storage:SetSetting("iconPulseSize", val)
            pulseSl:SetValue(val)
        end
        addon.AlertFrame:ApplyIconSize()
    end)

    pulseSl:SetScript("OnValueChanged", function(self, val)
        if panel and panel._refreshing then return end
        val = math.floor(val)
        local base = addon.Storage:GetSetting("iconBaseSize") or 64
        if val < base then
            self:SetValue(base)
            return
        end
        _G[self:GetName() .. "Text"]:SetText(self._labelText .. ": " .. val)
        addon.Storage:SetSetting("iconPulseSize", val)
        addon.AlertFrame:ApplyIconSize()
    end)

    return y
end

function MainFrame:_CreateSettings_LeadTime(panel, content, y)
    self:_MakeSectionLabel(content, "리드 타임 (알림 앞당김)", 8, y)
    y = y - 22

    local leadSl = self:_MakeSlider("HGTabLeadSl", "리드 타임 (초)", 0, 5, 0.1, content, y)
    leadSl:SetScript("OnValueChanged", function(self, val)
        if panel and panel._refreshing then return end
        val = math.floor(val * 10 + 0.5) / 10  -- 0.1 단위 반올림
        _G[self:GetName() .. "Text"]:SetText(string.format("%s: %.1fs", self._labelText, val))
        addon.Storage:SetSetting("leadTime", val)
    end)
    panel.leadSl = leadSl
    y = y - 50

    return y
end

function MainFrame:_CreateSettings_AlertDisplay(panel, content, y)
    self:_MakeSectionLabel(content, "알림 표현", 8, y)
    y = y - 22

    local soundCB = self:_MakeCheckbox("HGTabSoundCB", "사운드 재생", content, 8, y)
    soundCB:SetScript("OnClick", function(self)
        addon.Storage:SetSetting("soundEnabled", self:GetChecked() and true or false)
    end)
    panel.soundCB = soundCB

    local labelCB = self:_MakeCheckbox("HGTabLabelCB", "스킬명 표시", content, 150, y)
    labelCB:SetScript("OnClick", function(self)
        addon.Storage:SetSetting("showSpellName", self:GetChecked() and true or false)
    end)
    panel.labelCB = labelCB

    local ttsCB = self:_MakeCheckbox("HGTabTTSCB", "TTS 읽기", content, 292, y)
    ttsCB:SetScript("OnClick", function(self)
        local enabled = self:GetChecked() and true or false
        addon.Storage:SetSetting("ttsEnabled", enabled)
        MainFrame:_UpdateTTSGroupState()
    end)
    panel.ttsCB = ttsCB
    y = y - 32

    -- 큰 알림창(AlertFrame) 토글 — off 시 사운드/TTS 는 유지, 시각은 TimelineFrame 만 사용
    local alertFrameCB = self:_MakeCheckbox("HGTabAlertFrameCB", "큰 알림창 표시", content, 8, y)
    alertFrameCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("큰 알림창", 1, 1, 1)
        GameTooltip:AddLine("OFF: 사운드/TTS 만 재생하고 시각 알림은 타임라인(가로/세로 바) 만 사용.\n타임라인의 cast-moment 펄스로 충분하다면 끄는 걸 권장.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    alertFrameCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    alertFrameCB:SetScript("OnClick", function(self)
        addon.Storage:SetSetting("alertFrameEnabled", self:GetChecked() and true or false)
    end)
    panel.alertFrameCB = alertFrameCB
    y = y - 32

    local alertSlotsSl = self:_MakeSlider("HGTabAlertSlotsSl", "큰 알림창 동시 표시 수", 1, 4, 1, content, y)
    alertSlotsSl:SetScript("OnValueChanged", function(self, val)
        if panel and panel._refreshing then return end
        val = math.floor(val)
        _G[self:GetName() .. "Text"]:SetText(self._labelText .. ": " .. val)
        addon.Storage:SetSetting("alertFrameSlots", val)
    end)
    panel.alertSlotsSl = alertSlotsSl
    y = y - 50

    return y
end

function MainFrame:_CreateSettings_TTS(panel, ttsGroup)
    local gy = -4
    self:_MakeSectionLabel(ttsGroup, "TTS 세부", 8, gy)
    gy = gy - 22

    local voiceLabel = ttsGroup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    voiceLabel:SetPoint("TOPLEFT", ttsGroup, "TOPLEFT", 8, gy)
    voiceLabel:SetText("TTS 음성: —")
    panel.voiceLabel = voiceLabel

    local voicePickBtn = CreateFrame("Button", nil, ttsGroup, "GameMenuButtonTemplate")
    voicePickBtn:SetSize(80, 20)
    voicePickBtn:SetPoint("LEFT", voiceLabel, "RIGHT", 8, 0)
    voicePickBtn:SetText("선택 ▾")
    voicePickBtn:SetScript("OnClick", function(btn)
        MainFrame:_OpenVoiceMenu(btn)
    end)

    local ttsTestBtn = CreateFrame("Button", "HGTabTTSTestBtn", ttsGroup, "GameMenuButtonTemplate")
    ttsTestBtn:SetSize(60, 20)
    ttsTestBtn:SetPoint("LEFT", voicePickBtn, "RIGHT", 4, 0)
    ttsTestBtn:SetText("테스트")
    ttsTestBtn:SetScript("OnClick", function()
        if not (C_VoiceChat and C_VoiceChat.SpeakText) then return end
        -- 샘플 텍스트는 "치유의 기원"(Prayer of Mending, 33076) 스펠명을 런타임 조회.
        -- 클라이언트 언어에 자동 대응 → 한글 클라면 "치유의 기원", enUS 면 "Prayer of Mending".
        local sampleText = "HealGuide"
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, 33076)
            if ok and info and type(info.name) == "string" and info.name ~= "" then
                sampleText = info.name
            end
        end
        local voiceID = addon.Storage:GetSetting("ttsVoiceID") or 0
        local rate    = addon.Storage:GetSetting("ttsRate") or 5
        local volume  = addon.Storage:GetSetting("ttsVolume") or 100
        pcall(C_VoiceChat.SpeakText,
            voiceID,
            sampleText,
            Enum.VoiceTtsDestination and Enum.VoiceTtsDestination.LocalPlayback or 1,
            rate,
            volume
        )
    end)
    gy = gy - 28

    local rateSl = self:_MakeSlider("HGTabRateSl", "TTS 속도", 0, 10, 1, ttsGroup, gy)
    rateSl:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val)
        _G[self:GetName() .. "Text"]:SetText(self._labelText .. ": " .. val)
        addon.Storage:SetSetting("ttsRate", val)
    end)
    panel.rateSl = rateSl
    gy = gy - 50

    local volSl = self:_MakeSlider("HGTabVolSl", "TTS 볼륨", 0, 100, 1, ttsGroup, gy)
    volSl:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val)
        _G[self:GetName() .. "Text"]:SetText(self._labelText .. ": " .. val)
        addon.Storage:SetSetting("ttsVolume", val)
    end)
    panel.volSl = volSl
    gy = gy - 50

    return math.abs(gy) + 8
end

function MainFrame:_CreateSettings_AlertMode(panel, afterTts, ay)
    self:_MakeSectionLabel(afterTts, "알림 모드", 8, ay)
    ay = ay - 22

    panel.modeBtns = {}
    -- mode: 내부 키, label: 한글 라벨, desc: 툴팁 설명
    local MODES = {
        { mode = "reactive", label = "반응형",
          desc = "보스가 스킬을 쓴 순간 내 쿨기 추천을 알림.\n실제 로그 기반이라 가장 정확하지만, 알림이 '본 뒤 반응' 타이밍입니다." },
        { mode = "absolute", label = "절대시간",
          desc = "전투 시작 기준 고정 오프셋으로 미리 알림.\n보스 캐스트를 기다리지 않고 선타이밍 프리캐스트 가능하지만, 패턴이 어긋나면 빗나갈 수 있음." },
        { mode = "hybrid",   label = "혼합",
          desc = "절대시간으로 미리 띄우고, 실제 보스 캐스트 발생 시 보정.\n선타이밍 + 정확도를 모두 취하는 권장 모드." },
    }
    local modeXs = { 8, 130, 252 }
    for i, entry in ipairs(MODES) do
        local radioOk, btn = pcall(
            CreateFrame, "CheckButton", "HGTabModeBtn" .. i, afterTts, "UIRadioButtonTemplate")
        if not radioOk then
            btn = CreateFrame("CheckButton", "HGTabModeBtn" .. i, afterTts, "UICheckButtonTemplate")
        end
        btn:SetPoint("TOPLEFT", afterTts, "TOPLEFT", modeXs[i], ay + 4)
        btn._mode = entry.mode
        _G["HGTabModeBtn" .. i .. "Text"]:SetText(entry.label)

        -- 툴팁으로 설명 제공
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(entry.label, 1, 1, 1)
            GameTooltip:AddLine(entry.desc, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function(self)
            addon.Storage:SetSetting("alertMode", self._mode)
            for _, other in ipairs(panel.modeBtns) do
                other:SetChecked(other._mode == self._mode)
            end
        end)
        panel.modeBtns[i] = btn
    end
    ay = ay - 30

    return ay
end

function MainFrame:_CreateSettings_Sound(panel, afterTts, ay)
    self:_MakeSectionLabel(afterTts, "알림 사운드", 8, ay)
    ay = ay - 22

    local SOUND_PRESETS = {
        { id = 888,   label = "기본 (ReadyCheck)" },
        { id = 8959,  label = "레이드 경고" },
        { id = 8046,  label = "PVP 알림" },
        { id = 12889, label = "보석 획득" },
        { id = 11466, label = "퀘스트 완료" },
        { id = 3081,  label = "경고음" },
    }
    local soundLabel = afterTts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    soundLabel:SetPoint("TOPLEFT", afterTts, "TOPLEFT", 8, ay)
    panel.soundLabel = soundLabel

    local soundPickBtn = CreateFrame("Button", nil, afterTts, "GameMenuButtonTemplate")
    soundPickBtn:SetSize(80, 20)
    soundPickBtn:SetPoint("LEFT", soundLabel, "RIGHT", 8, 0)
    soundPickBtn:SetText("선택 ▾")
    soundPickBtn:SetScript("OnClick", function(btn)
        MainFrame:_ShowSoundDropdown(btn, SOUND_PRESETS)
    end)

    local soundTestBtn = CreateFrame("Button", nil, afterTts, "GameMenuButtonTemplate")
    soundTestBtn:SetSize(60, 20)
    soundTestBtn:SetPoint("LEFT", soundPickBtn, "RIGHT", 4, 0)
    soundTestBtn:SetText("테스트")
    soundTestBtn:SetScript("OnClick", function()
        PlaySound(addon.Storage:GetSetting("alertSoundID") or 888)
    end)
    ay = ay - 32

    return ay
end

function MainFrame:_CreateSettings_Condition(panel, afterTts, ay)
    self:_MakeSectionLabel(afterTts, "조건 엔진", 8, ay)
    ay = ay - 22

    local fallbackCB = self:_MakeCheckbox("HGTabFallbackCB", "조건 평가 실패 시 발화 (기본: ON)", afterTts, 8, ay)
    fallbackCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("조건 Fallback", 1, 1, 1)
        GameTooltip:AddLine("ON: 조건 평가 실패 시 알림 발화 (안전 모드)\nOFF: 조건 평가 실패 시 알림 생략", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    fallbackCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    fallbackCB:SetScript("OnClick", function(self)
        addon.Storage:SetSetting("conditionFallback", self:GetChecked() and true or false)
    end)
    panel.fallbackCB = fallbackCB
    ay = ay - 32

    return ay
end

function MainFrame:_CreateSettings_Developer(panel, afterTts, ay)
    self:_MakeSectionLabel(afterTts, "개발자", 8, ay)
    ay = ay - 22

    local debugCB = self:_MakeCheckbox("HGTabDebugCB", "디버그 로그", afterTts, 8, ay)
    debugCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("디버그 모드", 1, 1, 1)
        GameTooltip:AddLine("|cff888888[HG]|r 디버그 메시지를 채팅창에 표시합니다.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    debugCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    debugCB:SetScript("OnClick", function(self)
        addon.Storage:SetSetting("debugMode", self:GetChecked() and true or false)
    end)
    panel.debugCB = debugCB
    ay = ay - 30

    return ay
end

function MainFrame:_RefreshSettings()
    local panel = tabs[TAB_SETTINGS]
    if not panel then return end
    panel._refreshing = true
    -- pcall 로 감싸 에러 시에도 _refreshing 을 해제해서 설정 탭이 영구 불능 상태에 빠지지 않도록 보장
    local ok, err = pcall(function()
        local s = addon.Storage

        panel.lockCB:SetChecked(s:GetSetting("locked") and true or false)
        panel.soundCB:SetChecked(s:GetSetting("soundEnabled") and true or false)
        panel.labelCB:SetChecked(s:GetSetting("showSpellName") and true or false)
        panel.ttsCB:SetChecked(s:GetSetting("ttsEnabled") and true or false)
        panel.alertFrameCB:SetChecked(s:GetSetting("alertFrameEnabled") ~= false)
        panel.alertSlotsSl:SetValue(s:GetSetting("alertFrameSlots") or 1)

        panel.baseSl:SetValue(s:GetSetting("iconBaseSize")  or 64)
        panel.pulseSl:SetValue(s:GetSetting("iconPulseSize") or 96)
        panel.leadSl:SetValue(s:GetSetting("leadTime")  or 1.5)
        panel.rateSl:SetValue(s:GetSetting("ttsRate")   or 5)
        panel.volSl:SetValue(s:GetSetting("ttsVolume")  or 100)

        local pos = s:GetSetting("alertFramePoint") or { x = 0, y = 200 }
        panel.coordLabel:SetText(string.format("위치: %.0f, %.0f", pos.x or 0, pos.y or 200))

        local mode = s:GetSetting("alertMode")
        for _, btn in ipairs(panel.modeBtns) do
            btn:SetChecked(btn._mode == mode)
        end

        panel.fallbackCB:SetChecked(s:GetSetting("conditionFallback") and true or false)
        panel.debugCB:SetChecked(s:GetSetting("debugMode") and true or false)

        -- 타임라인
        panel.tlVisibleCB:SetChecked(s:GetSetting("timelineVisible") and true or false)
        panel.tlLockCB:SetChecked(s:GetSetting("timelineLocked") and true or false)
        panel.tlWindowSl:SetValue(s:GetSetting("timelineWindow") or 30)
        panel.tlIconSl:SetValue(s:GetSetting("timelineIconSize") or 36)
        panel.tlTrackSl:SetValue(s:GetSetting("timelineTrackLength") or 400)
        panel.tlTickCB:SetChecked(s:GetSetting("timelineShowTicks") and true or false)
        local tlOrient = s:GetSetting("timelineOrientation") or "horizontal"
        for _, btn in ipairs(panel.tlOrientBtns) do
            btn:SetChecked(btn._orient == tlOrient)
        end

        panel.ksMinSl:SetValue(s:GetSetting("keystoneMinLevel") or 2)
        if panel.ksLevelLabel then
            local ksLevel = addon.EncounterEngine and addon.EncounterEngine.keystoneLevel
            if ksLevel and ksLevel > 0 then
                panel.ksLevelLabel:SetText("현재 키: +" .. ksLevel)
            else
                panel.ksLevelLabel:SetText("현재 키: 비 쐐기")
            end
        end

        local soundID = s:GetSetting("alertSoundID") or 888
        panel.soundLabel:SetText("사운드: #" .. soundID)

        self:_RefreshVoiceLabel()
        self:_UpdateTTSGroupState()
    end)
    panel._refreshing = false
    if not ok then
        addon.dprint("_RefreshSettings error:", err)
    end
end

function MainFrame:_RefreshVoiceLabel()
    local panel = tabs[TAB_SETTINGS]
    if not panel then return end
    local voiceID = addon.Storage:GetSetting("ttsVoiceID") or 0
    local label   = "음성 #" .. voiceID

    -- C_VoiceChat.GetTtsVoices() 반환 구조는 클라이언트 버전별로 차이 가능.
    -- 필드명(voiceID/name) 접근을 pcall 로 감싸서 에러 시 기본 라벨 유지.
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
        if ok and type(voices) == "table" then
            for _, v in ipairs(voices) do
                if type(v) == "table" and v.voiceID == voiceID then
                    if type(v.name) == "string" then label = v.name end
                    break
                end
            end
        end
    end

    panel.voiceLabel:SetText("TTS 음성: " .. label)
end

function MainFrame:_UpdateTTSGroupState()
    local panel = tabs[TAB_SETTINGS]
    if not panel then return end
    if addon.Storage:GetSetting("ttsEnabled") then
        panel.ttsGroup:Show()
        panel.ttsGroup:SetHeight(panel._ttsGroupH)
    else
        panel.ttsGroup:Hide()
        panel.ttsGroup:SetHeight(0.01)
    end
end

function MainFrame:_OpenVoiceMenu(anchor)
    if not C_VoiceChat or not C_VoiceChat.GetTtsVoices then
        print("|cff00ff00HealGuide|r TTS 음성 API를 사용할 수 없습니다.")
        return
    end

    local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
    if not ok or type(voices) ~= "table" or #voices == 0 then
        print("|cff00ff00HealGuide|r TTS 음성 목록이 비어있거나 API 호출에 실패했습니다.")
        return
    end

    -- 11.x~12.x: MenuUtil.CreateContextMenu 우선, 구버전은 EasyMenu 폴백
    local entries = {}
    for _, v in ipairs(voices) do
        if type(v) == "table" and v.voiceID then
            local voiceID = v.voiceID
            local name    = (type(v.name) == "string" and v.name)
                or ("Voice " .. tostring(voiceID))
            entries[#entries + 1] = { voiceID = voiceID, name = name }
        end
    end

    if #entries == 0 then
        print("|cff00ff00HealGuide|r 사용 가능한 TTS 음성이 없습니다.")
        return
    end

    -- EasyMenu/MenuUtil 의존 없이 커스텀 드롭다운 프레임으로 구현 (12.0 호환성 이슈 회피)
    MainFrame:_ShowVoiceDropdown(anchor, entries)
end

local voiceDropdown = nil
function MainFrame:_ShowVoiceDropdown(anchor, entries)
    if voiceDropdown and voiceDropdown:IsShown() then
        voiceDropdown:Hide()
        return
    end
    if not voiceDropdown then
        voiceDropdown = CreateFrame("Frame", "HealGuideVoiceDropdown", UIParent, "BackdropTemplate")
        voiceDropdown:SetFrameStrata("TOOLTIP")
        voiceDropdown:EnableMouse(true)
        voiceDropdown:EnableKeyboard(true)
        voiceDropdown:SetPropagateKeyboardInput(false)
        tinsert(UISpecialFrames, "HealGuideVoiceDropdown")
        if voiceDropdown.SetBackdrop then
            voiceDropdown:SetBackdrop({
                bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
        end
    end

    -- 기존 버튼 제거
    if voiceDropdown._buttons then
        for _, b in ipairs(voiceDropdown._buttons) do b:Hide() end
    end
    voiceDropdown._buttons = {}

    local ROW_H = 18
    local PAD   = 6
    local maxW  = 120

    for i, e in ipairs(entries) do
        local btn = CreateFrame("Button", nil, voiceDropdown)
        btn:SetHeight(ROW_H)
        btn:SetPoint("TOPLEFT",  voiceDropdown, "TOPLEFT",  PAD, -PAD - (i - 1) * ROW_H)
        btn:SetPoint("TOPRIGHT", voiceDropdown, "TOPRIGHT", -PAD, -PAD - (i - 1) * ROW_H)

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", btn, "LEFT", 2, 0)
        fs:SetJustifyH("LEFT")
        fs:SetText(e.name)
        local w = fs:GetStringWidth() + 20
        if w > maxW then maxW = w end

        local voiceID = e.voiceID
        btn:SetScript("OnClick", function()
            addon.Storage:SetSetting("ttsVoiceID", voiceID)
            MainFrame:_RefreshVoiceLabel()
            voiceDropdown:Hide()
        end)
        voiceDropdown._buttons[i] = btn
    end

    voiceDropdown:SetSize(math.min(maxW, 280), PAD * 2 + #entries * ROW_H)
    voiceDropdown:ClearAllPoints()
    voiceDropdown:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    voiceDropdown:Show()
end

local soundDropdown = nil
function MainFrame:_ShowSoundDropdown(anchorBtn, presets)
    if soundDropdown and soundDropdown:IsShown() then
        soundDropdown:Hide()
        return
    end
    if not soundDropdown then
        soundDropdown = CreateFrame("Frame", "HealGuideSoundDropdown", UIParent, "BackdropTemplate")
        soundDropdown:SetFrameStrata("TOOLTIP")
        soundDropdown:EnableMouse(true)
        soundDropdown:EnableKeyboard(true)
        soundDropdown:SetPropagateKeyboardInput(false)
        tinsert(UISpecialFrames, "HealGuideSoundDropdown")
        if soundDropdown.SetBackdrop then
            soundDropdown:SetBackdrop({
                bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
        end
    end

    if soundDropdown._buttons then
        for _, b in ipairs(soundDropdown._buttons) do b:Hide() end
    end
    soundDropdown._buttons = {}

    local ROW_H, PAD = 18, 6
    local maxW = 140
    for i, preset in ipairs(presets) do
        local btn = CreateFrame("Button", nil, soundDropdown)
        btn:SetHeight(ROW_H)
        btn:SetPoint("TOPLEFT", soundDropdown, "TOPLEFT", PAD, -PAD - (i - 1) * ROW_H)
        btn:SetPoint("TOPRIGHT", soundDropdown, "TOPRIGHT", -PAD, -PAD - (i - 1) * ROW_H)

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", btn, "LEFT", 2, 0)
        fs:SetText(preset.label)
        local w = fs:GetStringWidth() + 20
        if w > maxW then maxW = w end

        btn:SetScript("OnClick", function()
            addon.Storage:SetSetting("alertSoundID", preset.id)
            PlaySound(preset.id)
            local panel = tabs[TAB_SETTINGS]
            if panel and panel.soundLabel then
                panel.soundLabel:SetText("사운드: " .. preset.label)
            end
            soundDropdown:Hide()
        end)
        soundDropdown._buttons[i] = btn
    end

    soundDropdown:SetSize(math.min(maxW, 280), PAD * 2 + #presets * ROW_H)
    soundDropdown:ClearAllPoints()
    soundDropdown:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    soundDropdown:Show()
end

-- ── Tab 3: 미리보기 ───────────────────────────────────────────────────────────

function MainFrame:_CreatePreviewTab(panel)
    local y = -12

    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y)
    desc:SetText("현재 설정(크기/펄스/사운드/TTS)을 그대로 시연합니다.")
    y = y - 24

    local alertBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    alertBtn:SetSize(140, 26)
    alertBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y)
    alertBtn:SetText("알림 테스트")
    alertBtn:SetScript("OnClick", function()
        addon.AlertFrame:ShowReminder(17)  -- Power Word: Shield
    end)
    y = y - 40

    local sep = panel:CreateTexture(nil, "BACKGROUND")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, y)
    sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, y)
    sep:SetColorTexture(0.3, 0.3, 0.3, 1)
    y = y - 14

    local simDesc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    simDesc:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y)
    simDesc:SetText("보스 시뮬레이션 (/hg test <encID> 와 동일)")
    y = y - 24

    local encInput = CreateFrame("EditBox", "HGEncIDInput", panel, "InputBoxTemplate")
    encInput:SetSize(120, 20)
    encInput:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y)
    encInput:SetAutoFocus(false)
    encInput:SetNumeric(true)
    encInput:SetMaxLetters(8)
    panel.encInput = encInput

    local simBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    simBtn:SetSize(90, 22)
    simBtn:SetPoint("LEFT", encInput, "RIGHT", 8, 0)
    simBtn:SetText("시뮬레이션")
    simBtn:SetScript("OnClick", function()
        local encID = tonumber(encInput:GetText())
        if encID then
            addon.EncounterEngine:TestEncounter(encID)
        else
            print("|cff00ff00HealGuide|r encID를 입력하세요.")
        end
    end)

    local stopBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    stopBtn:SetSize(70, 22)
    stopBtn:SetPoint("LEFT", simBtn, "RIGHT", 6, 0)
    stopBtn:SetText("|cffff6666중지|r")
    stopBtn:SetScript("OnClick", function()
        addon.EncounterEngine:Cancel()
        print("|cff00ff00HealGuide|r 시뮬레이션 중지")
    end)
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

function MainFrame:_MakeSectionLabel(parent, text, x, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText("|cffaaaaaa" .. text .. "|r")
    return lbl
end

function MainFrame:_MakeCheckbox(name, label, parent, x, y)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    _G[name .. "Text"]:SetText(label)
    return cb
end

function MainFrame:_MakeSlider(name, labelText, minV, maxV, step, parent, y)
    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetWidth(420)
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)
    _G[name .. "Low"]:SetText(tostring(minV))
    _G[name .. "High"]:SetText(tostring(maxV))
    _G[name .. "Text"]:SetText(labelText .. ": " .. minV)
    sl._labelText = labelText
    return sl
end

