local addonName, addon = ...
addon.CombatHistoryFrame = {}
local CombatHistoryFrame = addon.CombatHistoryFrame

local frame = nil

function CombatHistoryFrame:Toggle()
    if not frame then self:_Create() end
    if frame:IsShown() then
        frame:Hide()
    else
        self:_Refresh()
        frame:Show()
    end
end

function CombatHistoryFrame:_Create()
    frame = CreateFrame("Frame", "HealGuideCombatHistoryFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(420, 350)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.TitleText:SetText("HealGuide — 전투 이력")
    frame:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -26, 4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth() or 360)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    frame.content = content
    frame.rows = {}
end

function CombatHistoryFrame:_Refresh()
    if not frame then return end
    local db = HealGuideCharDB
    if not db or not db.combatHistory then return end

    local content = frame.content
    for _, row in ipairs(frame.rows) do row:Hide() end

    local y = -4
    local history = db.combatHistory
    -- 최신순 표시
    for i = #history, math.max(1, #history - 19), -1 do
        local record = history[i]
        if record then
            local row = frame.rows[#history - i + 1]
            if not row then
                row = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row:SetJustifyH("LEFT")
                row:SetWidth(content:GetWidth() or 360)
                frame.rows[#history - i + 1] = row
            end

            local stats = record.stats or {}
            local accuracy = (stats.fired and stats.fired > 0)
                and math.floor((stats.used or 0) / stats.fired * 100) or 0
            local duration = record.duration or 0
            local dateStr = record.timestamp and date("%m/%d %H:%M", record.timestamp) or "?"

            row:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
            row:SetText(string.format(
                "%s  |  Enc %d  |  알림 %d  사용 %d  적중 %d%%  |  %.0f초",
                dateStr,
                record.encounterID or 0,
                stats.fired or 0,
                stats.used or 0,
                accuracy,
                duration
            ))
            row:Show()
            y = y - 16
        end
    end

    content:SetHeight(math.abs(y) + 10)
end
