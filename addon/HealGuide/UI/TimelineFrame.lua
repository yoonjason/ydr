local addonName, addon = ...
addon.TimelineFrame = {}
local TimelineFrame = addon.TimelineFrame

local MAX_ICONS = 12
local anchor    = nil
local pool      = {}
local tickPool  = {}
local trackLine = nil

local function S(k) return addon.Storage:GetSetting(k) end

-- 데이터 근거: docs/mplus_integration_plan.md §4
local INTERRUPT_IDS = {
    [1254306] = true, -- Power Word: Shield (Lightward Healer, Magisters' Terrace)
    [473668]  = true, -- Pulsing Shriek (Devoted Woebringer, Windrunner's Spire)
    [1216592] = true, -- Chain Lightning (Phantasmal Mystic, Windrunner's Spire)
    [1257088] = true, -- Necrotic Wave (Dread Souleater, Maisara Caverns)
    [1256008] = true, -- Hex (Ritual Hexxer, Maisara Caverns)
    [248831]  = true, -- Dread Screech (Saprish, Seat of the Triumvirate)
    [396640]  = true, -- Healing Touch (Overgrown Ancient, Algeth'ar Academy)
    [1257595] = true, -- Divine Guile (Lothraxion, Nexus-Point X'enas)
}

local INTERRUPT_CAPABLE_SPECS = {
    MistweaverMonk = true, PresEvoker  = true, HolyPaladin = true,
    DiscPriest     = true, HolyPriest  = true, RestoShaman = true,
    RestoDruid     = true,
}

local function isPlayerSpecInterruptCapable()
    if not addon.SpecMatcher then return false end
    local spec = addon.SpecMatcher:GetActiveSpec()
    return spec ~= nil and INTERRUPT_CAPABLE_SPECS[spec] == true
end

-- ─── Tick pool (textures/fontstrings directly on anchor) ─────────────────────

local function acquireTick()
    for _, t in ipairs(tickPool) do
        if not t._inUse then
            t._inUse = true
            t.diamond:Show()
            t.label:Show()
            return t
        end
    end

    local diamond = anchor:CreateTexture(nil, "ARTWORK")
    diamond:SetColorTexture(0.85, 0.85, 0.85, 0.7)
    diamond:SetSize(7, 7)
    if diamond.SetRotation then diamond:SetRotation(math.pi / 4) end

    local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetTextColor(0.8, 0.8, 0.8, 0.9)

    local t = { diamond = diamond, label = label, _inUse = true }
    tickPool[#tickPool + 1] = t
    return t
end

local function releaseAllTicks()
    for _, t in ipairs(tickPool) do
        t._inUse = false
        t.diamond:Hide()
        t.label:Hide()
    end
end

-- ─── Icon pool ────────────────────────────────────────────────────────────────

local function acquireIcon()
    for _, ic in ipairs(pool) do
        if not ic._inUse then
            ic._inUse = true
            ic.btn:Show()
            return ic
        end
    end
    if #pool >= MAX_ICONS then return nil end

    local btn = CreateFrame("Button", nil, anchor)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.tex = tex

    -- 긴박 상태(3초 이하) 빨간 테두리 글로우
    local glow = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    glow:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -3,  3)
    glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  3, -3)
    glow:SetColorTexture(1, 0, 0, 0.35)
    glow:Hide()
    btn.glow = glow

    -- interrupt-critical 오렌지 border (§5C: 인터럽트 분담 마커)
    -- sublevel 7 이 최대 (OVERLAY sublevel 범위 -8~7). glow 보다 위에 오도록 7 유지.
    local interruptGlow = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    interruptGlow:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -2,  2)
    interruptGlow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  2, -2)
    interruptGlow:SetColorTexture(1.0, 0.6, 0.1, 0.4)
    interruptGlow:Hide()
    btn.interruptGlow = interruptGlow

    local timeText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timeText:SetPoint("CENTER")
    btn.timeText = timeText

    local ic = { btn = btn, tex = tex, glow = glow, interruptGlow = interruptGlow, timeText = timeText, _inUse = true }
    ic.glowLerp = { r = 0, g = 0, b = 0, a = 0 }
    pool[#pool + 1] = ic
    return ic
end

local function releaseAllIcons()
    for _, ic in ipairs(pool) do
        ic._inUse = false
        ic.btn:Hide()
        ic.glow:Hide()
        ic.interruptGlow:Hide()
        -- glowLerp 는 리셋하지 않음: 매 프레임 release/acquire 패턴에서 리셋 시 lerp 가 동작하지 않음.
        -- 전투 종료/orientation 전환 시 resetAllGlowLerp 로 별도 초기화.
    end
end

local function resetAllGlowLerp()
    for _, ic in ipairs(pool) do
        if ic.glowLerp then
            ic.glowLerp.r = 0; ic.glowLerp.g = 0; ic.glowLerp.b = 0; ic.glowLerp.a = 0
        end
    end
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function TimelineFrame:Init()
    anchor = CreateFrame("Frame", "HealGuideTimelineAnchor", UIParent)
    anchor:SetFrameStrata("MEDIUM")

    local pos = S("timelinePoint") or { point = "CENTER", relPoint = "CENTER", x = 0, y = -200 }
    anchor:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)

    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self)
        if not S("timelineLocked") then self:StartMoving() end
    end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        addon.Storage:SetSetting("timelinePoint", { point = point, relPoint = relPoint, x = x, y = y })
    end)

    trackLine = anchor:CreateTexture(nil, "BACKGROUND")
    trackLine:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    self:ApplyLayout()
    self:ApplyVisibility()

    for _ = 1, MAX_ICONS do
        local ic = acquireIcon()
        ic.btn:Hide()
        ic._inUse = false
    end
    -- 틱은 window=60 기준 최대 12개 (60/5)
    for _ = 1, 12 do
        local t = acquireTick()
        t.diamond:Hide()
        t.label:Hide()
        t._inUse = false
    end

    local elapsed = 0
    anchor:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.033 then return end
        elapsed = 0
        TimelineFrame:_Update()
    end)
end

function TimelineFrame:ApplyLayout()
    if not anchor then return end
    -- orientation 전환 시 lerp 상태가 남아있으면 재배치된 아이콘에 이전 색이 잠깐 스쳐 보임.
    resetAllGlowLerp()

    local orientation = S("timelineOrientation") or "horizontal"
    local trackLength = S("timelineTrackLength") or 400
    local iconSize    = S("timelineIconSize")    or 36

    trackLine:ClearAllPoints()
    if orientation == "horizontal" then
        anchor:SetSize(trackLength, iconSize + 20)
        -- 1px 가로 기준선: 앵커 수직 중앙을 관통
        trackLine:SetPoint("LEFT",  anchor, "LEFT",  0, 0)
        trackLine:SetPoint("RIGHT", anchor, "RIGHT", 0, 0)
        trackLine:SetHeight(1)
        trackLine:SetWidth(0)
    else
        anchor:SetSize(iconSize + 20, trackLength)
        -- 1px 세로 기준선: 앵커 수평 중앙을 관통
        trackLine:SetPoint("TOP",    anchor, "TOP",    0, 0)
        trackLine:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
        trackLine:SetWidth(1)
        trackLine:SetHeight(0)
    end
end

function TimelineFrame:ApplyVisibility()
    if not anchor then return end
    if S("timelineVisible") then anchor:Show() else anchor:Hide() end
end

function TimelineFrame:ResetPosition()
    if not anchor then return end
    local def = { point = "CENTER", relPoint = "CENTER", x = 0, y = -200 }
    addon.Storage:SetSetting("timelinePoint", def)
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
end

-- ─── Update loop ─────────────────────────────────────────────────────────────

function TimelineFrame:_Update()
    if not addon.EncounterEngine or not addon.EncounterEngine.activeEncounterID then
        releaseAllIcons()
        releaseAllTicks()
        resetAllGlowLerp()
        return
    end

    local orientation = S("timelineOrientation") or "horizontal"
    local window      = S("timelineWindow")      or 30
    local trackLength = S("timelineTrackLength") or 400
    local iconSize    = S("timelineIconSize")    or 36
    local showTicks   = S("timelineShowTicks")

    releaseAllIcons()
    releaseAllTicks()

    local upcoming = addon.EncounterEngine:GetUpcomingAlerts(20)
    local travel   = trackLength - iconSize

    -- ── 아이콘 배치 (remaining=1 이하에서 선형 스케일업 → 0 도달 시 자연 소멸) ──
    for _, data in ipairs(upcoming) do
        if data.remaining > 0 and data.remaining <= window then
            local ic = acquireIcon()
            if not ic then break end

            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(data.spellID)
            ic.tex:SetTexture((spellInfo and spellInfo.iconID) or 134400)

            local ampl = math.max(0, (5 - data.remaining) / 5) * 0.08
            local breathScale = 1.0 + ampl * math.sin(GetTime() * 5)
            local linearMult = data.remaining <= 1.0 and (1.0 + (1.0 - data.remaining) * 0.4) or 1.0
            local scale = breathScale * linearMult
            ic.btn:SetSize(iconSize * scale, iconSize * scale)
            ic.btn:SetAlpha(1)
            ic.btn:ClearAllPoints()

            local frac = 1 - (data.remaining / window)
            local cx   = frac * travel + iconSize / 2

            if orientation == "horizontal" then
                ic.btn:SetPoint("CENTER", anchor, "LEFT", cx, 0)
            else
                ic.btn:SetPoint("CENTER", anchor, "TOP", 0, -cx)
            end

            local secs = math.floor(data.remaining)
            ic.timeText:SetText(tostring(secs))

            -- glow lerp: target color/alpha by remaining band
            local tr, tg, tb, ta
            if data.remaining > 10 then
                tr, tg, tb, ta = 1, 0, 0, 0        -- fade out
            elseif data.remaining > 5 then
                tr, tg, tb, ta = 1, 0, 0, 0.5      -- red static
            else
                tr, tg, tb, ta = 1, 1, 1, 0.6      -- white static (or pulse)
            end

            local gl = ic.glowLerp
            local LERP = 0.11                       -- dt(0.033) / 0.3s ≈ 11% per frame
            gl.r = gl.r + (tr - gl.r) * LERP
            gl.g = gl.g + (tg - gl.g) * LERP
            gl.b = gl.b + (tb - gl.b) * LERP
            gl.a = gl.a + (ta - gl.a) * LERP

            local glowAlpha = gl.a
            if data.remaining <= 1.0 then
                local pulse = (math.sin(GetTime() * 8) + 1) * 0.5   -- 0..1, ~1.27Hz
                glowAlpha = 0.4 + pulse * 0.6                        -- 0.4..1.0
            end

            if glowAlpha > 0.01 then
                ic.glow:SetColorTexture(gl.r, gl.g, gl.b, glowAlpha)
                ic.glow:Show()
            else
                ic.glow:Hide()
            end

            -- text: red while 5 < remaining ≤ 10 (matches red glow band), else white
            if data.remaining > 5 and data.remaining <= 10 then
                ic.timeText:SetTextColor(1, 0.2, 0.2, 1)
            else
                ic.timeText:SetTextColor(1, 1, 1, 1)
            end

            if isPlayerSpecInterruptCapable() and INTERRUPT_IDS[data.spellID] then
                ic.interruptGlow:Show()
            else
                ic.interruptGlow:Hide()
            end
        end
    end

    -- ── 틱 마커 배치 ─────────────────────────────────────────────────────────────
    if showTicks then
        local t = 5
        while t <= window do
            local frac = 1 - (t / window)
            local cx   = frac * travel + iconSize / 2
            local tick = acquireTick()
            tick.label:SetText(tostring(t))
            tick.diamond:ClearAllPoints()
            tick.label:ClearAllPoints()

            if orientation == "horizontal" then
                tick.diamond:SetPoint("CENTER", anchor, "LEFT", cx, 0)
                tick.label:SetPoint("TOP", anchor, "LEFT", cx - 4, -(iconSize / 2 + 2))
            else
                tick.diamond:SetPoint("CENTER", anchor, "TOP", 0, -cx)
                tick.label:SetPoint("RIGHT", anchor, "TOP", -(iconSize / 2 + 4), -cx)
            end

            t = t + 5
        end
    end
end
