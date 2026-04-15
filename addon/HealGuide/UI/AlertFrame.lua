local addonName, addon = ...
addon.AlertFrame = {}
local AlertFrame = addon.AlertFrame

local frame = nil

function AlertFrame:Init()
    frame = CreateFrame("Frame", "HealGuideAlertFrame", UIParent)
    frame:SetSize(240, 60)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(100)

    local pos = addon.Storage:GetSetting("framePosition") or { x = 0, y = 200 }
    frame:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)

    -- 배경
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.75)

    -- 아이콘
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(48, 48)
    icon:SetPoint("LEFT", frame, "LEFT", 6, 0)
    frame.icon = icon

    -- 스킬 이름 텍스트
    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetPoint("LEFT", icon, "RIGHT", 8, 4)
    nameText:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    frame.nameText = nameText

    -- 드래그 지원
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not addon.Storage:GetSetting("locked") then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = UIParent:GetCenter()
        local fx, fy = self:GetCenter()
        addon.Storage:SetSetting("framePosition", { x = fx - cx, y = fy - cy })
    end)

    -- OnUpdate 로 페이드아웃 처리
    frame.elapsed  = 0
    frame.duration = 0
    frame:SetScript("OnUpdate", function(self, dt)
        if not self:IsShown() then return end
        self.elapsed = self.elapsed + dt
        local remaining = self.duration - self.elapsed
        if remaining <= 0 then
            self:Hide()
            return
        end
        if remaining < 0.5 then
            self:SetAlpha(remaining / 0.5)
        else
            self:SetAlpha(1.0)
        end
    end)

    frame:Hide()
end

function AlertFrame:ShowAlert(spellID)
    if not frame then return end

    local displaySec = addon.Storage:GetSetting("displaySeconds") or 2.0
    local name       = GetSpellInfo(spellID)
    local texture    = GetSpellTexture(spellID)

    frame.nameText:SetText(name or ("Spell " .. spellID))

    if texture then
        frame.icon:SetTexture(texture)
        frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        frame.icon:SetColorTexture(0.4, 0.4, 0.4, 1)
    end

    frame.elapsed  = 0
    frame.duration = displaySec
    frame:SetAlpha(1.0)
    frame:Show()
end

function AlertFrame:ToggleLock()
    local locked = addon.Storage:GetSetting("locked")
    addon.Storage:SetSetting("locked", not locked)
    if locked then
        print("|cff00ff00HealGuide|r 알림 프레임 잠금 해제 (드래그 가능)")
    else
        print("|cff00ff00HealGuide|r 알림 프레임 잠금")
    end
end
