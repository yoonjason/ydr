local addonName, addon = ...
addon.AlertFrame = {}
local AlertFrame = addon.AlertFrame

local DEFAULT_MAX_SLOTS = 4
local SLOT_GAP  = 4
local slots     = {}
local anchor    = nil

local function getLSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function playAlertSound()
    local s = addon.Storage
    if not s:GetSetting("soundEnabled") then return end
    local LSM       = getLSM()
    local soundName = s:GetSetting("alertSoundName")
    if LSM and soundName and soundName ~= "None" then
        local path = LSM:Fetch("sound", soundName, true)
        if path and path ~= "" then
            PlaySoundFile(path, "Master")
            return
        end
    end
    PlaySound(s:GetSetting("alertSoundID") or 888)
end

function AlertFrame:Init()
    anchor = CreateFrame("Frame", "HealGuideAlertAnchor", UIParent)
    anchor:SetSize(1, 1)
    anchor:SetFrameStrata("HIGH")

    local pos = addon.Storage:GetSetting("alertFramePoint")
        or { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 }
    anchor:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)

    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self)
        if addon.Storage:GetSetting("locked") then return end
        self:StartMoving()
    end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        addon.Storage:SetSetting("alertFramePoint", {
            point = point, relPoint = relPoint, x = x, y = y,
        })
        if addon.MainFrame and addon.MainFrame.UpdateCoordLabel then
            addon.MainFrame:UpdateCoordLabel(x, y)
        end
    end)

    anchor.editMode = false

    for i = 1, DEFAULT_MAX_SLOTS do
        slots[i] = self:_CreateSlot(i)
    end
end

function AlertFrame:_CreateSlot(index)
    local baseSize  = addon.Storage:GetSetting("iconBaseSize")  or 64
    local pulseSize = addon.Storage:GetSetting("iconPulseSize") or 96

    local frame = CreateFrame("Frame", "HealGuideAlertSlot" .. index, UIParent)
    frame:SetSize(pulseSize + 192, pulseSize + 12)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(100)
    frame:SetPoint("TOP", anchor, "TOP", 0, -((index - 1) * (pulseSize + 12 + SLOT_GAP)))

    -- slot 에서 직접 드래그 → anchor 이동 (anchor 가 1×1 px 라 직접 클릭 불가).
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        if not anchor or addon.Storage:GetSetting("locked") then return end
        anchor:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        if not anchor then return end
        anchor:StopMovingOrSizing()
        local point, _, relPoint, x, y = anchor:GetPoint()
        addon.Storage:SetSetting("alertFramePoint", {
            point = point, relPoint = relPoint, x = x, y = y,
        })
        if addon.MainFrame and addon.MainFrame.UpdateCoordLabel then
            addon.MainFrame:UpdateCoordLabel(x, y)
        end
    end)

    local bgColor = addon.Storage:GetSetting("alertBgColor") or { r = 0, g = 0, b = 0, a = 0.75 }
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    frame.bg = bg

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(baseSize, baseSize)
    icon:SetPoint("LEFT", frame, "LEFT", 6, 0)
    frame.icon = icon

    local LSM      = getLSM()
    local fontName = addon.Storage:GetSetting("alertFontName") or "Friz Quadrata TT"
    local fontSize = addon.Storage:GetSetting("alertFontSize") or 14
    local fontPath = LSM and LSM:Fetch("font", fontName, true)

    local nameText = frame:CreateFontString(nil, "OVERLAY")
    if fontPath then
        nameText:SetFont(fontPath, fontSize, "")
    else
        nameText:SetFontObject("GameFontNormalLarge")
    end
    nameText:SetPoint("LEFT",  icon,  "RIGHT", 8, 4)
    nameText:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    frame.nameText = nameText

    local textColor = addon.Storage:GetSetting("alertTextColor") or { r = 1, g = 1, b = 1, a = 1 }
    nameText:SetTextColor(textColor.r, textColor.g, textColor.b, textColor.a)

    local countdownText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    countdownText:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    countdownText:SetJustifyH("RIGHT")
    frame.countdownText = countdownText

    frame.pulse = {
        active = false, phase = nil, elapsed = 0,
        fromSize = baseSize, toSize = pulseSize, duration = 0,
    }
    frame.fadeElapsed  = 0
    frame.fadeDuration = 0
    frame.inUse        = false

    frame:SetScript("OnUpdate", function(self, dt)
        if not self:IsShown() or not self.inUse then return end
        if anchor and anchor.editMode then return end

        if self.pulse.active then
            self.pulse.elapsed = self.pulse.elapsed + dt
            local t = math.min(self.pulse.elapsed / self.pulse.duration, 1.0)
            local from, to = self.pulse.fromSize, self.pulse.toSize
            self.icon:SetSize(math.floor(from + (to - from) * t), math.floor(from + (to - from) * t))

            if t >= 1.0 then
                if self.pulse.phase == "up" then
                    local base = addon.Storage:GetSetting("iconBaseSize") or 64
                    self.pulse.phase    = "down"
                    self.pulse.elapsed  = 0
                    self.pulse.fromSize = self.pulse.toSize
                    self.pulse.toSize   = base
                    self.pulse.duration = 0.35
                else
                    self.pulse.active = false
                    local base = addon.Storage:GetSetting("iconBaseSize") or 64
                    self.icon:SetSize(base, base)
                end
            end
        end

        self.fadeElapsed = self.fadeElapsed + dt
        local remaining = self.fadeDuration - self.fadeElapsed
        if remaining <= 0 then
            self.inUse = false
            self.countdownText:SetText("")
            self:Hide()
            return
        end
        self:SetAlpha(remaining < 0.5 and (remaining / 0.5) or 1.0)
        self.countdownText:SetText(string.format("%.1fs", remaining))
    end)

    frame:Hide()
    return frame
end

function AlertFrame:_FindAvailableSlot()
    local maxSlots = math.min(addon.Storage:GetSetting("alertFrameSlots") or 1, DEFAULT_MAX_SLOTS)
    for i = 1, maxSlots do
        if not slots[i].inUse then return slots[i] end
    end
    return slots[maxSlots]
end

function AlertFrame:ShowAlert(spellID)
    if not anchor then return end

    local spellInfo = C_Spell.GetSpellInfo(spellID)
    local name      = spellInfo and spellInfo.name   or tostring(spellID)
    local texture   = spellInfo and spellInfo.iconID or 134400

    -- 사운드/TTS 는 항상 재생 (경고는 계속 듣고 싶을 수 있음).
    -- 큰 알림창 자체는 alertFrameEnabled 설정으로 제어 — TimelineFrame 으로 대체하는 사용자용.
    playAlertSound()

    local frameEnabled = addon.Storage:GetSetting("alertFrameEnabled")
    if frameEnabled == false then
        if addon.Storage:GetSetting("ttsEnabled") then
            self:_SpeakTTS(name)
        end
        return
    end

    local slot = self:_FindAvailableSlot()
    if not slot then return end

    local showName = addon.Storage:GetSetting("showSpellName")
    if showName then
        slot.nameText:SetText(name)
        slot.nameText:Show()
    else
        slot.nameText:Hide()
    end

    slot.icon:SetTexture(texture)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local baseSize  = addon.Storage:GetSetting("iconBaseSize")  or 64
    local pulseSize = addon.Storage:GetSetting("iconPulseSize") or 96

    slot.icon:SetSize(baseSize, baseSize)
    slot.pulse.active   = true
    slot.pulse.phase    = "up"
    slot.pulse.elapsed  = 0
    slot.pulse.fromSize = baseSize
    slot.pulse.toSize   = pulseSize
    slot.pulse.duration = 0.15

    slot.fadeElapsed  = 0
    slot.fadeDuration = addon.Storage:GetSetting("displaySeconds") or 2.0
    slot.inUse        = true
    slot:SetAlpha(1.0)
    slot:Show()

    if addon.Storage:GetSetting("ttsEnabled") then
        self:_SpeakTTS(name)
    end
end

AlertFrame.ShowReminder = AlertFrame.ShowAlert

function AlertFrame:EnterEditMode()
    if not anchor then return end
    anchor.editMode = true

    local baseSize = addon.Storage:GetSetting("iconBaseSize") or 64
    local slot = slots[1]
    if slot then
        slot.inUse = false
        slot.pulse.active = false
        slot.icon:SetSize(baseSize, baseSize)
        slot.icon:SetTexture(134400)
        slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot.nameText:SetText("|cffffcc00알림 위치 (드래그)|r")
        slot.nameText:Show()
        slot:SetAlpha(1.0)
        slot:Show()
    end
end

function AlertFrame:ExitEditMode()
    if not anchor then return end
    anchor.editMode = false
    for _, slot in ipairs(slots) do
        if not slot.inUse then slot:Hide() end
    end
end

function AlertFrame:IsEditMode()
    return anchor and anchor.editMode == true
end

function AlertFrame:_SpeakTTS(text)
    if not C_VoiceChat or not C_VoiceChat.SpeakText then return end
    local voiceID = addon.Storage:GetSetting("ttsVoiceID") or 0
    local rate    = addon.Storage:GetSetting("ttsRate")    or 5
    local volume  = addon.Storage:GetSetting("ttsVolume")  or 100
    local dest = (Enum and Enum.VoiceTtsDestination and Enum.VoiceTtsDestination.LocalPlayback) or 1
    pcall(C_VoiceChat.SpeakText, voiceID, text, dest, rate, volume)
end

function AlertFrame:ApplyIconSize()
    if not anchor then return end
    local baseSize  = addon.Storage:GetSetting("iconBaseSize")  or 64
    local pulseSize = addon.Storage:GetSetting("iconPulseSize") or 96
    for i, slot in ipairs(slots) do
        if not slot.pulse.active then
            slot.icon:SetSize(baseSize, baseSize)
        end
        slot:SetSize(pulseSize + 192, pulseSize + 12)
        slot:ClearAllPoints()
        slot:SetPoint("TOP", anchor, "TOP", 0, -((i - 1) * (pulseSize + 12 + SLOT_GAP)))
    end
end

function AlertFrame:ResetPosition()
    if not anchor then return end
    local defaultPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 }
    addon.Storage:SetSetting("alertFramePoint", defaultPos)
    anchor:ClearAllPoints()
    anchor:SetPoint(defaultPos.point, UIParent, defaultPos.relPoint, defaultPos.x, defaultPos.y)
    if addon.MainFrame and addon.MainFrame.UpdateCoordLabel then
        addon.MainFrame:UpdateCoordLabel(defaultPos.x, defaultPos.y)
    end
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

-- 테마(폰트·색상) 설정 변경 시 기존 슬롯에 즉시 반영
function AlertFrame:ApplyTheme()
    if not anchor then return end
    local LSM       = getLSM()
    local fontName  = addon.Storage:GetSetting("alertFontName") or "Friz Quadrata TT"
    local fontSize  = addon.Storage:GetSetting("alertFontSize") or 14
    local fontPath  = LSM and LSM:Fetch("font", fontName, true)
    local bgColor   = addon.Storage:GetSetting("alertBgColor")   or { r = 0, g = 0, b = 0,   a = 0.75 }
    local textColor = addon.Storage:GetSetting("alertTextColor") or { r = 1, g = 1, b = 1,   a = 1.0  }

    for _, slot in ipairs(slots) do
        if slot.bg then
            slot.bg:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
        end
        if slot.nameText then
            if fontPath then
                slot.nameText:SetFont(fontPath, fontSize, "")
            else
                slot.nameText:SetFontObject("GameFontNormalLarge")
            end
            slot.nameText:SetTextColor(textColor.r, textColor.g, textColor.b, textColor.a)
        end
    end
end
