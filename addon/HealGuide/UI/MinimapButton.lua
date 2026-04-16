local addonName, addon = ...
addon.MinimapButton = {}
local MinimapButton = addon.MinimapButton

local button = nil
local RADIUS = 80

function MinimapButton:Init()
    button = CreateFrame("Button", "HealGuideMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(54, 54)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(135940)  -- Spell_Holy_PowerWordShield
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(24, 24)
    highlight:SetPoint("CENTER")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local angle = addon.Storage:GetSetting("minimapAngle") or 220
    self:_SetPosition(angle)

    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            local modes = { "reactive", "absolute", "hybrid" }
            local current = addon.Storage:GetSetting("alertMode") or "reactive"
            local nextIndex = 1
            for i, mode in ipairs(modes) do
                if mode == current then
                    nextIndex = (i % #modes) + 1
                    break
                end
            end
            addon.Storage:SetSetting("alertMode", modes[nextIndex])
            print("|cff00ff00HealGuide|r 모드: " .. modes[nextIndex])
        else
            addon.MainFrame:Toggle()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self.dragging = true
    end)

    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        local x, y = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        local mx, my = Minimap:GetCenter()
        local dx, dy = x / scale - mx, y / scale - my
        local newAngle = math.deg(math.atan2(dy, dx))
        addon.Storage:SetSetting("minimapAngle", newAngle)
        MinimapButton:_SetPosition(newAngle)
    end)

    button:SetScript("OnUpdate", function(self)
        if self.dragging then
            local x, y = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local mx, my = Minimap:GetCenter()
            local dx, dy = x / scale - mx, y / scale - my
            local newAngle = math.deg(math.atan2(dy, dx))
            MinimapButton:_SetPosition(newAngle)
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("HealGuide")
        local mode = addon.Storage:GetSetting("alertMode") or "reactive"
        GameTooltip:AddLine("모드: " .. mode, 1, 1, 1)
        GameTooltip:AddLine("|cff888888좌클릭: 설정 열기|r")
        GameTooltip:AddLine("|cff888888우클릭: 모드 전환|r")
        GameTooltip:AddLine("|cff888888드래그: 위치 이동|r")
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function MinimapButton:_SetPosition(angle)
    if not button then return end
    local rads = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", RADIUS * math.cos(rads), RADIUS * math.sin(rads))
end
