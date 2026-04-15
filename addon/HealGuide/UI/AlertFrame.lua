local addonName, addon = ...
addon.AlertFrame = {}
local AlertFrame = addon.AlertFrame

local frame = nil

function AlertFrame:Init()
    local baseSize  = addon.Storage:GetSetting("iconBaseSize")  or 64
    local pulseSize = addon.Storage:GetSetting("iconPulseSize") or 96

    frame = CreateFrame("Frame", "HealGuideAlertFrame", UIParent)
    frame:SetSize(pulseSize + 192, pulseSize + 12)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(100)

    local pos = addon.Storage:GetSetting("alertFramePoint")
        or { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 }
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.75)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(baseSize, baseSize)
    icon:SetPoint("LEFT", frame, "LEFT", 6, 0)
    frame.icon = icon

    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetPoint("LEFT",  icon,  "RIGHT", 8, 4)
    nameText:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    frame.nameText = nameText

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        -- 편집 모드(= /hg 창 열림)이거나 잠금 해제 상태면 드래그 허용
        if self.editMode or not addon.Storage:GetSetting("locked") then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        addon.Storage:SetSetting("alertFramePoint", {
            point = point, relPoint = relPoint, x = x, y = y,
        })
        if addon.MainFrame and addon.MainFrame.UpdateCoordLabel then
            addon.MainFrame:UpdateCoordLabel(x, y)
        end
    end)

    -- 펄스 애니메이션 상태
    frame.pulse = {
        active   = false,
        phase    = nil,    -- "up" | "down"
        elapsed  = 0,
        fromSize = baseSize,
        toSize   = pulseSize,
        duration = 0,
    }

    frame.fadeElapsed  = 0
    frame.fadeDuration = 0

    frame:SetScript("OnUpdate", function(self, dt)
        if not self:IsShown() then return end
        -- 편집 모드에서는 페이드/펄스 건너뛰고 고정 표시
        if self.editMode then return end

        -- 펄스 애니메이션 (base → pulse → base)
        if self.pulse.active then
            self.pulse.elapsed = self.pulse.elapsed + dt
            local t = math.min(self.pulse.elapsed / self.pulse.duration, 1.0)
            local from, to = self.pulse.fromSize, self.pulse.toSize
            local cur = math.floor(from + (to - from) * t)
            self.icon:SetSize(cur, cur)

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

        -- 페이드아웃
        self.fadeElapsed = self.fadeElapsed + dt
        local remaining  = self.fadeDuration - self.fadeElapsed
        if remaining <= 0 then
            self:Hide()
            return
        end
        self:SetAlpha(remaining < 0.5 and (remaining / 0.5) or 1.0)
    end)

    frame.editMode = false
    frame:Hide()
end

-- 편집 모드: /hg 창이 열렸을 때 위치 조정용 플레이스홀더로 표시
function AlertFrame:EnterEditMode()
    if not frame then return end
    frame.editMode       = true
    frame.pulse.active   = false
    frame.fadeElapsed    = 0
    frame.fadeDuration   = 0

    local baseSize = addon.Storage:GetSetting("iconBaseSize") or 64
    frame.icon:SetSize(baseSize, baseSize)
    frame.icon:SetTexture(134400) -- 물음표 아이콘(플레이스홀더)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.nameText:SetText("|cffffcc00알림 위치 (드래그)|r")
    frame.nameText:Show()
    frame:SetAlpha(1.0)
    frame:Show()
end

function AlertFrame:ExitEditMode()
    if not frame then return end
    frame.editMode = false
    frame:Hide()
end

function AlertFrame:IsEditMode()
    return frame and frame.editMode == true
end

-- B1: C_Spell.GetSpellInfo 사용 (TWW 11.2+ deprecated API 교체)
function AlertFrame:ShowAlert(spellID)
    if not frame then return end

    local spellInfo = C_Spell.GetSpellInfo(spellID)
    local name      = spellInfo and spellInfo.name   or tostring(spellID)
    local texture   = spellInfo and spellInfo.iconID or 134400

    local showName = addon.Storage:GetSetting("showSpellName")
    if showName then
        frame.nameText:SetText(name)
        frame.nameText:Show()
    else
        frame.nameText:Hide()
    end

    frame.icon:SetTexture(texture)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- 이전 애니메이션 취소 후 재시작
    local baseSize  = addon.Storage:GetSetting("iconBaseSize")  or 64
    local pulseSize = addon.Storage:GetSetting("iconPulseSize") or 96

    frame.icon:SetSize(baseSize, baseSize)
    frame.pulse.active   = true
    frame.pulse.phase    = "up"
    frame.pulse.elapsed  = 0
    frame.pulse.fromSize = baseSize
    frame.pulse.toSize   = pulseSize
    frame.pulse.duration = 0.15

    frame.fadeElapsed  = 0
    frame.fadeDuration = addon.Storage:GetSetting("displaySeconds") or 2.0
    frame:SetAlpha(1.0)
    frame:Show()

    if addon.Storage:GetSetting("soundEnabled") then
        PlaySound(888)
    end

    if addon.Storage:GetSetting("ttsEnabled") then
        self:_SpeakTTS(name)
    end
end

-- ShowAlert 별칭 (미리보기 탭에서 사용)
AlertFrame.ShowReminder = AlertFrame.ShowAlert

-- TTS 발화. C_VoiceChat 사용 불가 환경이면 사일런트 폴백.
function AlertFrame:_SpeakTTS(text)
    if not C_VoiceChat or not C_VoiceChat.SpeakText then return end
    local voiceID = addon.Storage:GetSetting("ttsVoiceID") or 0
    local rate    = addon.Storage:GetSetting("ttsRate")    or 5
    local volume  = addon.Storage:GetSetting("ttsVolume")  or 100
    -- Enum.VoiceTtsDestination 가 제거된 클라이언트 대비 숫자 상수(1 = LocalPlayback) 폴백
    local dest = (Enum and Enum.VoiceTtsDestination and Enum.VoiceTtsDestination.LocalPlayback) or 1
    pcall(C_VoiceChat.SpeakText, voiceID, text, dest, rate, volume)
end

function AlertFrame:ApplyIconSize()
    if not frame then return end
    local baseSize  = addon.Storage:GetSetting("iconBaseSize")  or 64
    local pulseSize = addon.Storage:GetSetting("iconPulseSize") or 96
    -- 애니메이션 미진행 시에만 base 크기 즉시 반영
    if not frame.pulse.active then
        frame.icon:SetSize(baseSize, baseSize)
    end
    frame:SetSize(pulseSize + 192, pulseSize + 12)
end

function AlertFrame:ResetPosition()
    if not frame then return end
    local defaultPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 }
    addon.Storage:SetSetting("alertFramePoint", defaultPos)
    frame:ClearAllPoints()
    frame:SetPoint(defaultPos.point, UIParent, defaultPos.relPoint, defaultPos.x, defaultPos.y)
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
