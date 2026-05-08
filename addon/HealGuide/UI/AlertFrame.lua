local addonName, addon = ...
addon.AlertFrame = {}
local AlertFrame = addon.AlertFrame

local DEFAULT_MAX_SLOTS = 4
local SLOT_GAP  = 4
local slots     = {}
local anchor    = nil

-- TacticPanel 상태: 보스 시전 중 전술 텍스트 별도 채널
local tacticPanel       = nil
local tacticLineFonts   = {}
local activeTactics     = {}  -- [bossSpellID] = { {priority, action}, ... }
local sharedTacticLines = nil -- tactics["_shared"] 줄 배열 (보스 전체 주의사항)
local TACTIC_MAX_LINES  = 4
local TACTIC_COLOR  = {
    critical  = { 1, 0.33, 0.33 },
    important = { 1, 0.67, 0.27 },
    note      = { 0.7,  0.7, 0.7 },
}
local TACTIC_MARKER = { critical = "[!] ", important = "[~] ", note = "" }

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

    self:InitTacticPanel()
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

    -- 3단 fallback 시 주황 테두리: BORDER 레이어(ARTWORK 뒤)에 아이콘보다 3px 크게 배치
    local fallbackBorder = frame:CreateTexture(nil, "BORDER")
    fallbackBorder:SetPoint("TOPLEFT",     nil)  -- SetPoint 는 아래서 icon 기준으로 재설정
    fallbackBorder:SetColorTexture(1, 0.5, 0, 1)
    fallbackBorder:Hide()
    frame.fallbackBorder = fallbackBorder

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(baseSize, baseSize)
    icon:SetPoint("LEFT", frame, "LEFT", 6, 0)
    frame.icon = icon

    -- fallbackBorder 앵커를 icon 기준으로 설정 (icon 생성 이후)
    fallbackBorder:SetPoint("TOPLEFT",     icon, "TOPLEFT",     -3,  3)
    fallbackBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT",  3, -3)

    local LSM      = getLSM()
    local fontName = addon.Storage:GetSetting("alertFontName") or "Friz Quadrata TT"
    local fontSize = addon.Storage:GetSetting("alertFontSize") or 14
    local fontPath = LSM and LSM:Fetch("font", fontName, true)
    -- koKR/zhCN/zhTW 에서 LSM 기본 폰트(Friz Quadrata TT)는 CJK 미지원이라 ㅁㅁㅁ 으로 깨짐
    do
        local locale = GetLocale and GetLocale() or "enUS"
        if (locale == "koKR" or locale == "zhCN" or locale == "zhTW")
            and fontName == "Friz Quadrata TT" and STANDARD_TEXT_FONT then
            fontPath = STANDARD_TEXT_FONT
        end
    end

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

    -- 전술 가이드 1줄 (보스 스킬 시전 시 힐러 대응 방법). 색상은 priority 에 따라
    -- ShowAlert 에서 동적 설정.
    -- 앵커: icon 기준 (nameText Hide 여부 무관하게 고정 위치). nameText 하단과 비슷한
    -- 높이에 배치되도록 y 오프셋 = -(fontSize + 2).
    local tacticText = frame:CreateFontString(nil, "OVERLAY")
    if fontPath then
        tacticText:SetFont(fontPath, math.max(10, fontSize - 4), "")
    else
        tacticText:SetFontObject("GameFontNormalSmall")
    end
    tacticText:SetPoint("TOPLEFT",  icon,  "RIGHT",  8, -(fontSize + 2))
    tacticText:SetPoint("TOPRIGHT", frame, "RIGHT", -40, -(fontSize + 2))
    tacticText:SetJustifyH("LEFT")
    -- 긴 전술은 줄바꿈 허용 (2줄까지). 초과분은 자연 truncate.
    tacticText:SetWordWrap(true)
    tacticText:SetMaxLines(2)
    tacticText:Hide()
    frame.tacticText = tacticText

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

-- ShowAlert(spellID, tacticText?, tacticPriority?, category?)
--   tacticText:     '떨어지는 구슬 받아주기' 같은 전술 대응 1줄 (옵션)
--   tacticPriority: "critical" / "important" / "note" — 색상 결정
--   category:       "fallback" 이면 아이콘에 주황 테두리 표시 (3단 fallback 시각 구분)
function AlertFrame:ShowAlert(spellID, tacticText, tacticPriority, category)
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

    -- 전술 라인 표시 (있으면). priority 로 색상 구분:
    --   critical=빨강, important=주황, note=사용자 테마색
    if slot.tacticText then
        if type(tacticText) == "string" and tacticText ~= "" then
            local r, g, b, a = 1, 1, 1, 1
            if tacticPriority == "critical" then
                r, g, b = 1, 0.33, 0.33
            elseif tacticPriority == "important" then
                r, g, b = 1, 0.67, 0.27
            else
                -- note / 기타 — 사용자 테마 색상 따름 (nameText 와 일관)
                local themeColor = addon.Storage:GetSetting("alertTextColor") or { r = 1, g = 1, b = 1, a = 1 }
                r, g, b, a = themeColor.r, themeColor.g, themeColor.b, themeColor.a
            end
            slot.tacticText:SetText(tacticText)
            slot.tacticText:SetTextColor(r, g, b, a)
            slot.tacticText:Show()
        else
            slot.tacticText:Hide()
        end
    end

    -- fallback 카테고리: 주황 테두리 표시 / 해제
    if slot.fallbackBorder then
        if category == "fallback" then
            slot.fallbackBorder:Show()
        else
            slot.fallbackBorder:Hide()
        end
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

-- ── TacticPanel ───────────────────────────────────────────────────────────────

function AlertFrame:InitTacticPanel()
    local LSM      = getLSM()
    local fontName = addon.Storage:GetSetting("alertFontName") or "Friz Quadrata TT"
    local fontSize = math.max(10, (addon.Storage:GetSetting("alertFontSize") or 14) - 2)
    local fontPath = LSM and LSM:Fetch("font", fontName, true)
    do
        local locale = GetLocale and GetLocale() or "enUS"
        if (locale == "koKR" or locale == "zhCN" or locale == "zhTW")
            and fontName == "Friz Quadrata TT" and STANDARD_TEXT_FONT then
            fontPath = STANDARD_TEXT_FONT
        end
    end
    local lineH    = fontSize + 4

    tacticPanel = CreateFrame("Frame", "HealGuideTacticPanel", UIParent)
    tacticPanel:SetFrameStrata("HIGH")
    tacticPanel:SetFrameLevel(99)
    tacticPanel:SetClampedToScreen(true)

    local pos = addon.Storage:GetSetting("tacticPanelPoint")
        or { point = "CENTER", relPoint = "CENTER", x = 0, y = 100 }
    tacticPanel:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    tacticPanel:SetSize(320, TACTIC_MAX_LINES * lineH + 10)

    local bgColor = addon.Storage:GetSetting("alertBgColor") or { r = 0, g = 0, b = 0, a = 0.75 }
    local bg = tacticPanel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    tacticPanel.bg = bg

    tacticPanel:EnableMouse(true)
    tacticPanel:SetMovable(true)
    tacticPanel:RegisterForDrag("LeftButton")
    tacticPanel:SetScript("OnDragStart", function(self)
        if addon.Storage:GetSetting("locked") then return end
        self:StartMoving()
    end)
    tacticPanel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        addon.Storage:SetSetting("tacticPanelPoint", {
            point = point, relPoint = relPoint, x = x, y = y,
        })
    end)

    for i = 1, TACTIC_MAX_LINES do
        local fs = tacticPanel:CreateFontString(nil, "OVERLAY")
        if fontPath then
            fs:SetFont(fontPath, fontSize, "")
        else
            fs:SetFontObject("GameFontNormalSmall")
        end
        fs:SetHeight(lineH)
        fs:SetPoint("TOPLEFT",  tacticPanel, "TOPLEFT",   5, -(4 + (i - 1) * lineH))
        fs:SetPoint("TOPRIGHT", tacticPanel, "TOPRIGHT", -5, -(4 + (i - 1) * lineH))
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:Hide()
        tacticLineFonts[i] = fs
    end

    tacticPanel:Hide()
end

-- SetSharedTactics: 보스 전체 주의사항 (_shared 줄 배열). 인카운터 시작 시 설정,
-- 종료 시 HideAllTactics 로 nil 처리.
function AlertFrame:SetSharedTactics(lines)
    sharedTacticLines = (type(lines) == "table" and #lines > 0) and lines or nil
end

-- ShowTactics: 특정 보스 스킬 시전 시작 — 스킬별 전술 줄 표시
function AlertFrame:ShowTactics(spellID, lines)
    if type(lines) ~= "table" or #lines == 0 then return end
    activeTactics[spellID] = lines
    self:_RenderTactics()
end

-- HideTactics: 특정 보스 스킬 시전 종료 — 해당 스킬 전술 줄만 제거
function AlertFrame:HideTactics(spellID)
    activeTactics[spellID] = nil
    self:_RenderTactics()
end

-- HideAllTactics: 인카운터 종료 / Cancel 시 전체 초기화
function AlertFrame:HideAllTactics()
    activeTactics     = {}
    sharedTacticLines = nil
    self:_RenderTactics()
end

function AlertFrame:_RenderTactics()
    if not tacticPanel then return end

    if next(activeTactics) == nil and (not sharedTacticLines or #sharedTacticLines == 0) then
        tacticPanel:Hide()
        for i = 1, TACTIC_MAX_LINES do tacticLineFonts[i]:Hide() end
        return
    end

    -- _shared 줄 먼저 수집, 그 다음 스킬별 줄 (4줄 제한)
    local combined = {}
    if type(sharedTacticLines) == "table" then
        for _, t in ipairs(sharedTacticLines) do
            combined[#combined + 1] = t
        end
    end
    for _, lines in pairs(activeTactics) do
        for _, t in ipairs(lines) do
            combined[#combined + 1] = t
        end
    end

    local shown = 0
    for i = 1, TACTIC_MAX_LINES do
        local t  = combined[i]
        local fs = tacticLineFonts[i]
        if t and type(t.action) == "string" and t.action ~= "" then
            local col    = TACTIC_COLOR[t.priority] or TACTIC_COLOR.note
            local marker = TACTIC_MARKER[t.priority] or ""
            fs:SetTextColor(col[1], col[2], col[3], 1)
            fs:SetText(marker .. t.action)
            fs:Show()
            shown = shown + 1
        else
            fs:SetText("")
            fs:Hide()
        end
    end

    if shown > 0 then tacticPanel:Show() else tacticPanel:Hide() end
end

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
    do
        local locale = GetLocale and GetLocale() or "enUS"
        if (locale == "koKR" or locale == "zhCN" or locale == "zhTW")
            and fontName == "Friz Quadrata TT" and STANDARD_TEXT_FONT then
            fontPath = STANDARD_TEXT_FONT
        end
    end
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
        -- tacticText 폰트도 테마 반영 (색상은 priority 별로 ShowAlert 에서 재지정).
        if slot.tacticText then
            if fontPath then
                slot.tacticText:SetFont(fontPath, math.max(10, fontSize - 4), "")
            else
                slot.tacticText:SetFontObject("GameFontNormalSmall")
            end
        end
    end

    -- TacticPanel 테마 반영
    if tacticPanel then
        if tacticPanel.bg then
            tacticPanel.bg:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
        end
        local tacticFontSize = math.max(10, fontSize - 2)
        for _, fs in ipairs(tacticLineFonts) do
            if fontPath then
                fs:SetFont(fontPath, tacticFontSize, "")
            else
                fs:SetFontObject("GameFontNormalSmall")
            end
        end
    end
end
