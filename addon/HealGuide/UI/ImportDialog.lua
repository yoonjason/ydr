local addonName, addon = ...
addon.ImportDialog = {}
local ImportDialog = addon.ImportDialog

local dialog          = nil
local targetDungeonKey = nil  -- nil=신규, 문자열=갱신 대상

function ImportDialog:Open(dungeonKey)
    targetDungeonKey = dungeonKey

    if not dialog then
        self:_Create()
    end

    dialog.editBox:SetText("")
    dialog.statusText:SetText("")
    dialog:Show()
    dialog.editBox:SetFocus()
end

function ImportDialog:_Create()
    dialog = CreateFrame("Frame", "HealGuideImportDialog", UIParent, "BasicFrameTemplateWithInset")
    dialog:SetSize(520, 420)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop",  dialog.StopMovingOrSizing)
    dialog:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then self:Hide() end
    end)

    dialog.TitleText:SetText("HealGuide — Import")

    -- 안내 텍스트
    local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", dialog.InsetBg, "TOPLEFT", 8, -8)
    hint:SetText("Mac 앱에서 복사한 import 문자열을 붙여넣으세요:")

    -- 스크롤 EditBox
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     hint,            "BOTTOMLEFT",  0,   -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", dialog.InsetBg, "BOTTOMRIGHT", -26,  40)

    local editBox = CreateFrame("EditBox", "HealGuideImportEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
    scrollFrame:SetScrollChild(editBox)
    dialog.editBox = editBox

    -- 상태 메시지
    local statusText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("BOTTOMLEFT",  dialog.InsetBg, "BOTTOMLEFT",  8,   8)
    statusText:SetPoint("BOTTOMRIGHT", dialog.InsetBg, "BOTTOMRIGHT", -90, 8)
    statusText:SetJustifyH("LEFT")
    dialog.statusText = statusText

    -- 등록 버튼
    local importBtn = CreateFrame("Button", nil, dialog, "GameMenuButtonTemplate")
    importBtn:SetSize(80, 22)
    importBtn:SetPoint("BOTTOMRIGHT", dialog.InsetBg, "BOTTOMRIGHT", -4, 6)
    importBtn:SetText("등록")
    importBtn:SetScript("OnClick", function()
        ImportDialog:_DoImport()
    end)

    -- 취소 버튼
    local cancelBtn = CreateFrame("Button", nil, dialog, "GameMenuButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("RIGHT", importBtn, "LEFT", -4, 0)
    cancelBtn:SetText("취소")
    cancelBtn:SetScript("OnClick", function()
        dialog:Hide()
    end)
end

function ImportDialog:_DoImport()
    local text = dialog.editBox:GetText()

    local data, err = addon.ImportParser:Parse(text)
    if err then
        dialog.statusText:SetText("|cffff4444오류: " .. err .. "|r")
        return
    end

    if targetDungeonKey then
        addon.Storage:UpdateDungeon(targetDungeonKey, data)
        dialog.statusText:SetText("|cff00ff44갱신 완료: " .. data.dungeonName .. " (" .. data.spec .. ")|r")
    else
        addon.Storage:AddDungeon(data)
        dialog.statusText:SetText("|cff00ff44등록 완료: " .. data.dungeonName .. " (" .. data.spec .. ")|r")
    end

    addon.MainFrame:Refresh()

    C_Timer.After(1.5, function()
        if dialog:IsShown() then dialog:Hide() end
    end)
end
