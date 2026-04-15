local addonName, addon = ...
addon.MainFrame = {}
local MainFrame = addon.MainFrame

local mainFrame = nil

function MainFrame:Init()
    self:_Create()
end

function MainFrame:Toggle()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        self:Refresh()
        mainFrame:Show()
    end
end

function MainFrame:_Create()
    mainFrame = CreateFrame("Frame", "HealGuideMainFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(540, 500)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop",  mainFrame.StopMovingOrSizing)
    mainFrame:Hide()

    mainFrame.TitleText:SetText("HealGuide")

    -- 헤더: 캐릭터 / 스펙 정보
    local headerText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    headerText:SetPoint("TOPLEFT", mainFrame.InsetBg, "TOPLEFT", 8, -8)
    mainFrame.headerText = headerText

    -- 던전 목록 스크롤 영역
    local scrollFrame = CreateFrame("ScrollFrame", nil, mainFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     headerText,      "BOTTOMLEFT",  0,   -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame.InsetBg, "BOTTOMRIGHT", -26, 40)
    mainFrame.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth() or 480)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    mainFrame.content = content

    -- 하단 버튼 바
    local importBtn = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
    importBtn:SetSize(130, 22)
    importBtn:SetPoint("BOTTOMLEFT", mainFrame.InsetBg, "BOTTOMLEFT", 4, 6)
    importBtn:SetText("+ 새 던전 import")
    importBtn:SetScript("OnClick", function()
        addon.ImportDialog:Open()
    end)

    local modeLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    modeLabel:SetPoint("LEFT", importBtn, "RIGHT", 10, 0)
    modeLabel:SetText("모드:")

    local modeBtn = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
    modeBtn:SetSize(90, 22)
    modeBtn:SetPoint("LEFT", modeLabel, "RIGHT", 4, 0)
    mainFrame.modeBtn = modeBtn

    local MODES = { "reactive", "absolute", "hybrid" }
    modeBtn:SetScript("OnClick", function()
        local current = addon.Storage:GetSetting("alertMode")
        local idx = 1
        for i, m in ipairs(MODES) do
            if m == current then idx = i; break end
        end
        local next = MODES[(idx % #MODES) + 1]
        addon.Storage:SetSetting("alertMode", next)
        modeBtn:SetText(next)
    end)

    local settingsBtn = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
    settingsBtn:SetSize(36, 22)
    settingsBtn:SetPoint("LEFT", modeBtn, "RIGHT", 4, 0)
    settingsBtn:SetText("⚙")
    settingsBtn:SetScript("OnClick", function()
        MainFrame:_OpenSettings()
    end)
end

-- 메인 Refresh: 전체 던전 목록을 재구성
function MainFrame:Refresh()
    if not mainFrame then return end

    local spec     = addon.SpecMatcher:GetActiveSpec() or "비힐러"
    local charName = UnitName("player") or "?"
    mainFrame.headerText:SetText(charName .. "  —  " .. spec)
    mainFrame.modeBtn:SetText(addon.Storage:GetSetting("alertMode"))

    -- 기존 content 자식 프레임 제거
    local content = mainFrame.content
    local children = { content:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end

    -- 던전 목록 정렬 (importedAt 오래된 순)
    local dungeons    = addon.Storage:GetDungeons()
    local sortedKeys  = {}
    for k in pairs(dungeons) do
        table.insert(sortedKeys, k)
    end
    table.sort(sortedKeys, function(a, b)
        return (dungeons[a].importedAt or 0) < (dungeons[b].importedAt or 0)
    end)

    local yOffset   = -4
    local totalWidth = content:GetWidth() or 480

    for _, dungeonKey in ipairs(sortedKeys) do
        local rowH = self:_CreateDungeonBlock(content, dungeonKey, dungeons[dungeonKey], yOffset, totalWidth)
        yOffset = yOffset - rowH - 4
    end

    content:SetHeight(math.abs(yOffset) + 10)
end

-- 던전 블록 1개 생성, 소비한 높이 반환
function MainFrame:_CreateDungeonBlock(parent, dungeonKey, dungeon, yOffset, width)
    local HEADER_H = 28
    local BOSS_H   = 20

    local bossCount = 0
    for _ in pairs(dungeon.bosses) do bossCount = bossCount + 1 end

    local totalH = HEADER_H + bossCount * BOSS_H

    local block = CreateFrame("Frame", nil, parent)
    block:SetSize(width, totalH)
    block:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)

    -- 배경 (짝수/홀수 구분 없이 단일 색상)
    local bg = block:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.5)

    -- ON/OFF 토글
    local toggleBtn = CreateFrame("Button", nil, block, "GameMenuButtonTemplate")
    toggleBtn:SetSize(40, 20)
    toggleBtn:SetPoint("TOPLEFT", block, "TOPLEFT", 4, -4)
    toggleBtn:SetText(dungeon.enabled and "|cff00ff00ON|r" or "|cffff4444OFF|r")
    toggleBtn:SetScript("OnClick", function()
        addon.Storage:SetDungeonEnabled(dungeonKey, not dungeon.enabled)
        MainFrame:Refresh()
    end)

    -- 던전 이름
    local nameText = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT",  toggleBtn, "RIGHT", 6, 0)
    nameText:SetPoint("RIGHT", block,     "RIGHT", 160, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    local label = dungeon.displayName
    if dungeon.originalName ~= dungeon.displayName then
        label = label .. " |cff888888(" .. dungeon.originalName .. ")|r"
    end
    nameText:SetText(label)

    -- 이름 변경
    local renameBtn = CreateFrame("Button", nil, block, "GameMenuButtonTemplate")
    renameBtn:SetSize(66, 20)
    renameBtn:SetPoint("TOPRIGHT", block, "TOPRIGHT", -112, -4)
    renameBtn:SetText("이름변경")
    renameBtn:SetScript("OnClick", function()
        self:_OpenRenameDialog(dungeonKey, dungeon.displayName)
    end)

    -- 갱신
    local refreshBtn = CreateFrame("Button", nil, block, "GameMenuButtonTemplate")
    refreshBtn:SetSize(40, 20)
    refreshBtn:SetPoint("LEFT", renameBtn, "RIGHT", 2, 0)
    refreshBtn:SetText("갱신")
    refreshBtn:SetScript("OnClick", function()
        addon.ImportDialog:Open(dungeonKey)
    end)

    -- 삭제
    local deleteBtn = CreateFrame("Button", nil, block, "GameMenuButtonTemplate")
    deleteBtn:SetSize(40, 20)
    deleteBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 2, 0)
    deleteBtn:SetText("|cffff4444삭제|r")
    deleteBtn:SetScript("OnClick", function()
        StaticPopupDialogs["HEALGUIDE_CONFIRM_DELETE"] = {
            text    = "\"" .. dungeon.displayName .. "\" 를 삭제하시겠습니까?",
            button1 = "삭제",
            button2 = "취소",
            OnAccept = function()
                addon.Storage:RemoveDungeon(dungeonKey)
                MainFrame:Refresh()
            end,
            timeout       = 0,
            whileDead     = true,
            hideOnEscape  = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("HEALGUIDE_CONFIRM_DELETE")
    end)

    -- 보스 목록 (들여쓰기)
    local bossY = -HEADER_H
    for encounterID, boss in pairs(dungeon.bosses) do
        local bossRow = CreateFrame("Frame", nil, block)
        bossRow:SetSize(width - 20, BOSS_H)
        bossRow:SetPoint("TOPLEFT", block, "TOPLEFT", 20, bossY)

        local specList = {}
        if boss.specs then
            for s in pairs(boss.specs) do
                table.insert(specList, s)
            end
            table.sort(specList)
        end
        local specStr = #specList > 0 and (" |cff888888[" .. table.concat(specList, ", ") .. "]|r") or ""

        local bossText = bossRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bossText:SetPoint("LEFT", bossRow, "LEFT", 0, 0)
        bossText:SetText("|cffaaaaaa" .. (boss.name or "?") .. "|r  " .. encounterID .. specStr)

        bossY = bossY - BOSS_H
    end

    return totalH
end

function MainFrame:_OpenRenameDialog(dungeonKey, currentName)
    StaticPopupDialogs["HEALGUIDE_RENAME"] = {
        text         = "새 이름을 입력하세요:",
        button1      = "확인",
        button2      = "취소",
        hasEditBox   = true,
        OnShow       = function(self)
            self.editBox:SetText(currentName)
            self.editBox:HighlightText()
        end,
        OnAccept     = function(self)
            local newName = self.editBox:GetText():match("^%s*(.-)%s*$")
            if newName ~= "" then
                addon.Storage:SetDungeonDisplayName(dungeonKey, newName)
                MainFrame:Refresh()
            end
        end,
        timeout       = 0,
        whileDead     = true,
        hideOnEscape  = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("HEALGUIDE_RENAME")
end

function MainFrame:_OpenSettings()
    -- 간단한 설정 토글 (사운드)
    local sound = addon.Storage:GetSetting("soundEnabled")
    addon.Storage:SetSetting("soundEnabled", not sound)
    print("|cff00ff00HealGuide|r 사운드: " .. (not sound and "ON" or "OFF"))
end
