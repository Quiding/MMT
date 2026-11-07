-- MMT Statistics: the live tracker, a small window of its own (option "Show
-- live tracker"): the session (since login or /reload) of the character you
-- play - its length, time on the current level, XP %, and XP, gold and kills
-- in the session and per hour. "Reset" starts a new session in this window
-- only; the statistics themselves are not touched.
-- Redrawn at most once a second after a change, else every 15 seconds.

local _, mod = ...
local MMT = MMT
local M = mod.M

local Safe, IsSecret = MMT.Safe, MMT.IsSecret
local function Plain(v) if v == nil or IsSecret(v) then return nil end return v end
local function Num(f, ...) return tonumber(Plain(Safe(f, ...))) end

local A = { 0.31, 0.70, 1.00 }
local PAD = 4

---------------------------------------------------------------------------
-- Session
---------------------------------------------------------------------------
local session = { start = GetTime(), xp = 0 }
local lastLevel, lastXP, lastMax

local function Kills()
    local c = mod.Char()
    return c and c.killTotal or 0
end

local function StartSession()
    session.start = GetTime()
    session.xp = 0
    session.money = Num(GetMoney)
    session.kills = Kills()
    lastLevel, lastXP, lastMax = Num(UnitLevel, "player"), Num(UnitXP, "player"), Num(UnitXPMax, "player")
end

local function OnXP()
    local L, xp, max = Num(UnitLevel, "player"), Num(UnitXP, "player"), Num(UnitXPMax, "player")
    if not (L and xp and max) then return end
    if lastLevel and lastXP then
        local gain
        if L == lastLevel then gain = xp - lastXP
        elseif L > lastLevel then gain = math.max(0, (lastMax or 0) - lastXP) + xp end
        if gain and gain > 0 then session.xp = session.xp + gain end
    end
    lastLevel, lastXP, lastMax = L, xp, max
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local f, cells, lines

local function Thousands(n)
    local s = tostring(math.floor(math.abs(n) + 0.5))
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (n < 0 and "-" or "") .. s
end

local function Clock(sec)
    sec = math.max(0, math.floor(sec or 0))
    return ("%02d:%02d"):format(math.floor(sec / 3600), math.floor(sec / 60) % 60)
end

local function SignedMoney(copper)
    if copper < 0 then return "-" .. mod.Money(-copper) end
    return mod.Money(copper)
end

local function Font(fs, scale)
    MMT.ApplyFont(fs, M.db.liveFont or "Friz Quadrata", math.floor((M.db.liveSize or 10) * (scale or 1) + 0.5), "OUTLINE")
end

local function SavePoint()
    local point, _, relPoint, x, y = f:GetPoint()
    M.db.livePoint = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
end

local function Build()
    f = CreateFrame("Frame", "MMTStatsLiveTracker", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not M.db.liveLocked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePoint() end)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.6)
    f.line = f:CreateTexture(nil, "BORDER")
    f.line:SetPoint("TOPLEFT"); f.line:SetPoint("TOPRIGHT")
    f.line:SetHeight(1)
    f.line:SetColorTexture(A[1], A[2], A[3], 0.8)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.title:SetText("Live tracker")
    f.title:SetTextColor(A[1], A[2], A[3])
    f.close = CreateFrame("Button", nil, f)
    f.close.text = f.close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.close.text:SetPoint("CENTER")
    f.close.text:SetText("x")
    f.close.text:SetTextColor(0.6, 0.6, 0.6)
    f.close:SetScript("OnClick", function() M.db.liveTracker = false mod.UpdateLiveTracker() end)
    f.close:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Hide the live tracker")
        GameTooltip:AddLine("Turn it on again under Statistics > Settings.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.close:SetScript("OnLeave", function(self) self.text:SetTextColor(0.6, 0.6, 0.6) GameTooltip:Hide() end)

    -- Session / On this level / XP: label left, value right
    lines = {}
    for i = 1, 3 do
        lines[i] = { l = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), v = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
        lines[i].l:SetJustifyH("LEFT")
        lines[i].l:SetTextColor(0.75, 0.75, 0.75)
        lines[i].v:SetJustifyH("RIGHT")
    end
    lines[1].l:SetText("Session")
    lines[2].l:SetText("On this level")
    lines[3].l:SetText("XP")

    -- table: 4 rows (head, XP, Gold, Kills) x 3 columns
    cells = {}
    for r = 1, 4 do
        cells[r] = {}
        for c = 1, 3 do
            local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH(c == 1 and "LEFT" or "RIGHT")
            fs:SetWordWrap(false)
            if r == 1 or c == 1 then fs:SetTextColor(0.75, 0.75, 0.75) end
            cells[r][c] = fs
        end
    end
    cells[1][1]:SetText("")
    cells[1][2]:SetText("Session")
    cells[1][3]:SetText("per hour")
    cells[2][1]:SetText("XP")
    cells[3][1]:SetText("Gold")
    cells[4][1]:SetText("Kills")
    f.sep = f:CreateTexture(nil, "BORDER")
    f.sep:SetHeight(1)
    f.sep:SetColorTexture(1, 1, 1, 0.12)

    f.reset = CreateFrame("Button", nil, f)
    f.reset.bg = f.reset:CreateTexture(nil, "BACKGROUND")
    f.reset.bg:SetAllPoints()
    f.reset.bg:SetColorTexture(1, 1, 1, 0.06)
    f.reset.text = f.reset:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.reset.text:SetPoint("CENTER")
    f.reset.text:SetText("Reset session")
    f.reset:SetScript("OnClick", function() StartSession() mod.RedrawLiveTracker(true) end)
    f.reset:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(A[1], A[2], A[3], 0.25)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Reset session")
        GameTooltip:AddLine("Starts a new session in this window. The statistics themselves are not changed.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.reset:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, 0.06) GameTooltip:Hide() end)
    f:Hide()
end

-- places everything for the font size; returns nothing
local function Layout()
    local size = M.db.liveSize or 10
    local h = size + 3
    Font(f.title, 1)
    for _, ln in ipairs(lines) do Font(ln.l) Font(ln.v) end
    for r = 1, 4 do for c = 1, 3 do Font(cells[r][c]) end end
    Font(f.close.text)
    Font(f.reset.text, 0.9)

    -- widths from the font size (values change, the window should not jump)
    local w1, w2, w3 = size * 4, size * 7, size * 7
    local width = PAD * 2 + w1 + w2 + w3
    f.icon:SetSize(size + 2, size + 2)
    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT", PAD, -PAD)
    f.title:ClearAllPoints()
    f.title:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
    f.close:SetSize(h, h)
    f.close:ClearAllPoints()
    f.close:SetPoint("TOPRIGHT", -2, -PAD + 2)
    local y = -PAD - (size + 2) - 4
    for _, ln in ipairs(lines) do
        ln.l:ClearAllPoints(); ln.v:ClearAllPoints()
        if ln.hidden then
            ln.l:Hide(); ln.v:Hide()
        else
            ln.l:Show(); ln.v:Show()
            ln.l:SetPoint("TOPLEFT", PAD, y)
            ln.v:SetPoint("TOPRIGHT", -PAD, y)
            ln.v:SetWidth(width - PAD * 2 - size * 6)
            y = y - h
        end
    end
    y = y - 3
    for r = 1, 4 do
        local x = PAD
        for c, w in ipairs({ w1, w2, w3 }) do
            local fs = cells[r][c]
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", x, y)
            fs:SetWidth(w)
            x = x + w
        end
        y = y - h
        if r == 1 then
            f.sep:ClearAllPoints()
            f.sep:SetPoint("TOPLEFT", PAD, y + 1)
            f.sep:SetPoint("TOPRIGHT", -PAD, y + 1)
        end
    end
    y = y - 3
    f.reset:ClearAllPoints()
    f.reset:SetPoint("TOPLEFT", PAD, y)
    f.reset:SetPoint("TOPRIGHT", -PAD, y)
    f.reset:SetHeight(h + 2)
    y = y - (h + 2) - PAD
    f:SetSize(width, -y)
end

local function MaxLevel()
    local m = GetMaxPlayerLevel and Num(GetMaxPlayerLevel)
    return m or MAX_PLAYER_LEVEL or 60
end

local lastDraw, dirty = 0, false
local hideLevel   -- the "On this level" line was hidden at the last layout

function mod.RedrawLiveTracker(now)
    if not (f and f:IsShown()) then return end
    if not now and GetTime() - lastDraw < 1 then dirty = true return end
    lastDraw, dirty = GetTime(), false
    local elapsed = GetTime() - session.start
    local L = Num(UnitLevel, "player") or 0
    local atMax = L >= MaxLevel()

    -- hide "On this level" at max level (layout changes only then)
    if (atMax and true or false) ~= hideLevel then
        hideLevel = atMax and true or false
        lines[2].hidden = hideLevel
        Layout()
    end

    lines[1].v:SetText(Clock(elapsed))
    local c = mod.Char()
    local rec = c and c.levels and c.levels[L]
    lines[2].v:SetText(rec and Clock(rec.t) or "-")
    local xp, max, rested = Num(UnitXP, "player"), Num(UnitXPMax, "player"), Num(GetXPExhaustion)
    if atMax or not (xp and max) or max <= 0 then
        lines[3].v:SetText("max level")
    else
        local text = ("%.1f%%"):format(xp / max * 100)
        if rested and rested > 0 then text = text .. ("  |cffbf99ff(%d%%)|r"):format(math.floor(rested / max * 100 + 0.5)) end
        lines[3].v:SetText(text)
    end

    local hours = elapsed / 3600
    local function PerHour(v) return elapsed >= 60 and (v / hours) or nil end
    local money = (Num(GetMoney) or 0) - (session.money or Num(GetMoney) or 0)
    local kills = Kills() - (session.kills or Kills())
    local xpH, moneyH, killsH = PerHour(session.xp), PerHour(money), PerHour(kills)
    cells[2][2]:SetText(Thousands(session.xp))
    cells[2][3]:SetText(xpH and Thousands(xpH) or "-")
    cells[3][2]:SetText(SignedMoney(money))
    cells[3][3]:SetText(moneyH and SignedMoney(math.floor(moneyH)) or "-")
    cells[4][2]:SetText(Thousands(kills))
    cells[4][3]:SetText(killsH and ("%.1f"):format(killsH) or "-")
end

-- shown or hidden by the setting (and with the module)
function mod.UpdateLiveTracker()
    local want = M.enabled and M.db.liveTracker and true or false
    if not want then
        if f then f:Hide() end
        return
    end
    if not f then Build() end
    local p = M.db.livePoint or { "TOPLEFT", "TOPLEFT", 300, -200 }
    f:ClearAllPoints()
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    hideLevel = nil
    f:Show()
    Layout()
    mod.RedrawLiveTracker(true)
end

local function Changed() mod.RedrawLiveTracker() end
M:On("PLAYER_XP_UPDATE", function(unit)
    if unit and unit ~= "player" then return end
    OnXP()
    Changed()
end)
M:On("PLAYER_LEVEL_UP", Changed)
M:On("PLAYER_MONEY", Changed)
M:On("UPDATE_EXHAUSTION", Changed)
-- kills: Kills.lua counts them (no event of its own): the 1 s ticker below catches them
local lastKills
M:On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(2, function()
        if not session.money then StartSession() end
        mod.UpdateLiveTracker()
    end)
end)

C_Timer.NewTicker(1, function()
    if not (f and f:IsShown()) then return end
    local k = Kills()
    if k ~= lastKills then lastKills = k dirty = true end
    if dirty or GetTime() - lastDraw >= 15 then mod.RedrawLiveTracker(true) end
end)

local oldEnable, oldDisable, oldProfile = M.OnEnable, M.OnDisable, M.OnProfileChanged
M.OnEnable = function(...)
    if oldEnable then oldEnable(...) end
    C_Timer.After(2, function()
        if not session.money then StartSession() end
        mod.UpdateLiveTracker()
    end)
end
M.OnDisable = function(...)
    if oldDisable then oldDisable(...) end
    mod.UpdateLiveTracker()
end
M.OnProfileChanged = function(...)
    if oldProfile then oldProfile(...) end
    mod.UpdateLiveTracker()
end

-- /mmt debug dump: what the window shows
local oldReport = M.Report
M.Report = function(m, add)
    if oldReport then oldReport(m, add) end
    if not (f and f:IsShown()) then add("  live tracker: off") return end
    local out = {}
    for _, ln in ipairs(lines) do
        if not ln.hidden then out[#out + 1] = tostring(ln.l:GetText()) .. "=" .. tostring(ln.v:GetText()) end
    end
    for r = 2, 4 do
        out[#out + 1] = ("%s=%s/%s per h"):format(tostring(cells[r][1]:GetText()), tostring(cells[r][2]:GetText()), tostring(cells[r][3]:GetText()))
    end
    add("  live tracker: " .. table.concat(out, "  "))
end
