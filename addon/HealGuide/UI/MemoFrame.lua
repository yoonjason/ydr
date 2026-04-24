local addonName, addon = ...
addon.MemoFrame = {}
local MemoFrame = addon.MemoFrame

local memoFrame = nil
local memoText  = nil
local memoBg    = nil

local function getLSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function resolveFontPath(size)
    local LSM      = getLSM()
    local fontName = addon.Storage:GetSetting("alertFontName") or "Friz Quadrata TT"
    local path     = LSM and LSM:Fetch("font", fontName, true)
    return path or "Fonts\\FRIZQT__.TTF", math.max(10, math.min(32, size or 14))
end

-- ── Public API ───────────────────────────────────────────────────────────────

function MemoFrame:Init()
    local memo     = addon.Storage:GetSetting("memo") or {}
    local fontSize = memo.fontSize or 14
    local fc       = memo.fontColor or { r = 1, g = 1, b = 1 }
    local bgAlpha  = (memo.bgAlpha or 60) / 100

    memoFrame = CreateFrame("Frame", "HealGuideMemoFrame", UIParent)
    memoFrame:SetFrameStrata("HIGH")
    memoFrame:SetFrameLevel(90)
    memoFrame:SetClampedToScreen(true)
    memoFrame:SetSize(400, 40)

    local pos = memo.point or { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 }
    memoFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)

    memoBg = memoFrame:CreateTexture(nil, "BACKGROUND")
    memoBg:SetAllPoints()
    memoBg:SetColorTexture(0, 0, 0, bgAlpha)

    memoText = memoFrame:CreateFontString(nil, "OVERLAY")
    local fontPath, sz = resolveFontPath(fontSize)
    memoText:SetFont(fontPath, sz, "")
    memoText:SetPoint("TOPLEFT",  memoFrame, "TOPLEFT",   6, -6)
    memoText:SetPoint("TOPRIGHT", memoFrame, "TOPRIGHT",  -6, -6)
    memoText:SetJustifyH("LEFT")
    memoText:SetJustifyV("TOP")
    memoText:SetWordWrap(true)
    memoText:SetTextColor(fc.r, fc.g, fc.b, 1)

    memoFrame:EnableMouse(true)
    memoFrame:SetMovable(true)
    memoFrame:RegisterForDrag("LeftButton")
    memoFrame:SetScript("OnDragStart", function(self)
        local m = addon.Storage:GetSetting("memo")
        if m and m.locked then return end
        self:StartMoving()
    end)
    memoFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local m = addon.Storage:GetSetting("memo")
        if m and m.locked then return end
        local point, _, relPoint, x, y = self:GetPoint()
        if m then
            m.point = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    self:RefreshFromStorage()
end

-- 텍스트 + 프레임 높이 갱신
function MemoFrame:Refresh()
    if not memoFrame then return end
    local memo  = addon.Storage:GetSetting("memo") or {}
    local lines = type(memo.lines) == "table" and memo.lines or {}
    memoText:SetText(table.concat(lines, "\n"))

    local fontSize = memo.fontSize or 14
    local lineH    = math.max(10, fontSize) + 4
    local numLines = memoText:GetNumLines()
    if numLines < 1 then numLines = math.max(1, #lines) end
    memoFrame:SetHeight(math.max(30, numLines * lineH + 12))
end

-- 표시/숨김
function MemoFrame:SetVisible(show)
    if not memoFrame then return end
    if show then memoFrame:Show() else memoFrame:Hide() end
end

-- 프로파일 전환 등 외부 변경 시 폰트/색/배경 + 텍스트 + 표시 상태 일괄 갱신
function MemoFrame:RefreshFromStorage()
    if not memoFrame then return end
    local memo = addon.Storage:GetSetting("memo") or {}

    local fontSize = memo.fontSize  or 14
    local fc       = memo.fontColor or { r = 1, g = 1, b = 1 }
    local bgAlpha  = (memo.bgAlpha  or 60) / 100

    local fontPath, sz = resolveFontPath(fontSize)
    memoText:SetFont(fontPath, sz, "")
    memoText:SetTextColor(fc.r, fc.g, fc.b, 1)
    memoBg:SetColorTexture(0, 0, 0, bgAlpha)

    self:Refresh()
    self:SetVisible(memo.show ~= false)
end
