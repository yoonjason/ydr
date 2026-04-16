local addonName, addon = ...
addon.TimerBarFrame = {}
local TimerBarFrame = addon.TimerBarFrame

local MAX_BARS    = 6
local BAR_HEIGHT  = 24
local BAR_GAP     = 2
local BAR_WIDTH   = 220
local anchor      = nil
local bars        = {}

function TimerBarFrame:Init()
    anchor = CreateFrame("Frame", "HealGuideTimerAnchor", UIParent)
    anchor:SetSize(BAR_WIDTH, 1)
    anchor:SetFrameStrata("MEDIUM")

    local pos = addon.Storage:GetSetting("timerBarPoint")
        or { point = "CENTER", relPoint = "CENTER", x = 200, y = 200 }
    anchor:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self)
        if not addon.Storage:GetSetting("locked") then self:StartMoving() end
    end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        addon.Storage:SetSetting("timerBarPoint", { point = point, relPoint = relPoint, x = x, y = y })
    end)

    for i = 1, MAX_BARS do
        bars[i] = self:_CreateBar(i)
    end

    anchor:SetScript("OnUpdate", function(_, dt)
        TimerBarFrame:_Update()
    end)
end

function TimerBarFrame:_CreateBar(index)
    local bar = CreateFrame("StatusBar", "HealGuideTimerBar" .. index, anchor)
    bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
    bar:SetPoint("TOP", anchor, "TOP", 0, -((index - 1) * (BAR_HEIGHT + BAR_GAP)))
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.2, 0.6, 1.0, 0.8)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)

    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(BAR_HEIGHT - 2, BAR_HEIGHT - 2)
    icon:SetPoint("LEFT", bar, "LEFT", 2, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.icon = icon

    local nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameText:SetPoint("RIGHT", bar, "RIGHT", -40, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    bar.nameText = nameText

    local timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    timeText:SetJustifyH("RIGHT")
    bar.timeText = timeText

    bar.spellID = nil
    bar.maxDuration = 0
    bar:Hide()
    return bar
end

function TimerBarFrame:_Update()
    if not addon.EncounterEngine or not addon.EncounterEngine.activeEncounterID then
        for _, bar in ipairs(bars) do bar:Hide() end
        return
    end

    local upcoming = addon.EncounterEngine:GetUpcomingAlerts(MAX_BARS)

    for i = 1, MAX_BARS do
        local bar = bars[i]
        local data = upcoming[i]

        if data then
            local spellInfo = C_Spell.GetSpellInfo(data.spellID)
            local name    = spellInfo and spellInfo.name or tostring(data.spellID)
            local texture = spellInfo and spellInfo.iconID or 134400

            bar.icon:SetTexture(texture)
            bar.nameText:SetText(name)
            bar.timeText:SetText(string.format("%.1f", data.remaining))

            if bar.spellID ~= data.spellID or bar.maxDuration < data.remaining then
                bar.maxDuration = data.remaining
                bar.spellID = data.spellID
            end

            if bar.maxDuration > 0 then
                bar:SetValue(data.remaining / bar.maxDuration)
            else
                bar:SetValue(1)
            end

            -- 3초 이하: 바 색상 변경 (긴급)
            if data.remaining <= 3 then
                bar:SetStatusBarColor(1.0, 0.3, 0.3, 0.9)
            elseif data.remaining <= 8 then
                bar:SetStatusBarColor(1.0, 0.8, 0.2, 0.9)
            else
                bar:SetStatusBarColor(0.2, 0.6, 1.0, 0.8)
            end

            bar:Show()
        else
            bar:Hide()
            bar.spellID = nil
            bar.maxDuration = 0
        end
    end
end
