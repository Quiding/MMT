-- MMT Quest Tracker: completed quest XP, shown like rested XP in a colour of its own.
-- The XP itself comes from the core (MMT 1.1.0+, LevelUp.lua): every client adds up
-- the reward XP of its quests that are ready to turn in and sends it with the
-- heartbeat ("qx"); MMT.TurnInXP(key) reads it for any member. This file only shows it:
--   * in the Info window as the piece "Completed quest XP" (Q 20%), which also shades
--     each member's bar right after the fill (core XPPieces.lua, bar = fn),
--   * on the game's own XP bar, for this character (setting questXPGameBar): a frame
--     of our own laid over the bar. Nothing of the Blizzard bar is replaced, hooked
--     or written to: writing Blizzard functions or globals taints them (QoL "No
--     flash" did that), and a frame of our own only reads the bar's size.
-- On the game's bar the shade lies over the game's rested fill (both start where the XP
-- ends); the smaller of the two is drawn on top, so neither hides the other.
-- The shade stops at the end of the bar, with a bright edge there, when turning in
-- would reach the next level; the piece then shows more than 100%.

local _, mod = ...
local MMT = MMT
local M = mod.M

local function Num(v)
    if type(v) ~= "number" or MMT.IsSecret(v) then return nil end
    return v
end

local function AtMaxLevel()
    local level = UnitLevel("player") or 0
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    return level >= maxLevel or (IsXPUserDisabled and IsXPUserDisabled()) or false
end

---------------------------------------------------------------------------
-- The XP of a member (the piece and the bars)
---------------------------------------------------------------------------
function mod.QuestXPOf(key, s)
    if not M.enabled or not M.db.questXP then return 0 end
    if not s or s.isMax or (s.max or 0) <= 0 then return 0 end
    return MMT.TurnInXP and tonumber(MMT.TurnInXP(key, s)) or 0
end

local function Colour()
    local c = M.db.questXPColour or {}
    return c.r or 1, c.g or 0.72, c.b or 0.15, M.db.questXPAlpha or 0.55
end

local function Hex(r, g, b)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

-- readable on a dark background, whatever the shade's colour
local function TextHex()
    local r, g, b = Colour()
    return Hex(0.35 + r * 0.65, 0.35 + g * 0.65, 0.35 + b * 0.65)
end

MMT.RegisterXPPiece{
    id = "questxp", title = "Completed quest XP (%)", side = "RIGHT", on = true, before = "rep",
    sample = Hex(1, 0.8, 0.4) .. "Q 20%|r",
    tip = "XP of the quests ready to turn in, in percent of the current level, e.g. Q 20% (over 100%: enough for the next level). Also shaded on the bar after the XP, in its own colour (Quest Tracker > Quest XP).",
    text = function(key, s)
        if MMT.db.xp.barMode == "REP" then return nil end
        local xp = mod.QuestXPOf(key, s)
        if xp <= 0 then return nil end
        return TextHex() .. ("Q %d%%"):format(math.floor(xp / s.max * 100 + 0.5)) .. "|r"
    end,
    bar = function(key, s) return mod.QuestXPOf(key, s) end,
    barColour = Colour,
}

---------------------------------------------------------------------------
-- The game's XP bar: a frame of our own over its StatusBar
---------------------------------------------------------------------------
local overlay

-- the StatusBar of the game's XP bar and its rested fill: the retail-style containers
-- of this client (MainStatusTrackingBarContainer, the bar with the rested fill), else
-- the old MainMenuExpBar. Only read, never changed.
local function GameXPStatusBar()
    for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
        local c = rawget(_G, name)
        if type(c) == "table" and type(c.bars) == "table" then
            for _, bar in pairs(c.bars) do
                if type(bar) == "table" and bar.ExhaustionLevelFillBar and type(bar.StatusBar) == "table" then
                    return bar.StatusBar, bar.ExhaustionLevelFillBar
                end
            end
        end
    end
    local old = rawget(_G, "MainMenuExpBar")
    if type(old) == "table" and type(old.GetObjectType) == "function" and old:GetObjectType() == "StatusBar" then
        return old, rawget(_G, "ExhaustionLevelFillBar")
    end
end

-- our copy of the rested part looks like the game's rested fill (its atlas or texture
-- and colour, only read), else the XP window's rested colour
local function LookLikeRested(tex, fill)
    local ok = pcall(function()
        local region = fill
        if fill.GetObjectType and fill:GetObjectType() == "StatusBar" then region = fill:GetStatusBarTexture() end
        local atlas = region.GetAtlas and region:GetAtlas()
        if type(atlas) == "string" and atlas ~= "" then
            tex:SetAtlas(atlas)
        else
            local file = region:GetTexture()
            if not file then error("no texture") end
            tex:SetTexture(file)
        end
        local r, g, b, a = region:GetVertexColor()
        tex:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
        tex:SetAlpha(fill:GetAlpha() or 1)
    end)
    if not ok then tex:SetColorTexture(0.65, 0.45, 1.0, 0.6) end
end
mod.GameXPStatusBar = GameXPStatusBar

local function Overlay(statusBar)
    if not overlay then
        overlay = CreateFrame("Frame", nil, statusBar)
        overlay:EnableMouse(false)
        overlay.shade = overlay:CreateTexture(nil, "ARTWORK")
        overlay.edge = overlay:CreateTexture(nil, "ARTWORK", nil, 1)
        overlay.edge:SetWidth(2)
        overlay.edge:SetPoint("TOPRIGHT"); overlay.edge:SetPoint("BOTTOMRIGHT")
        -- rested XP again, over the shade when it is the smaller one (else hidden under it)
        overlay.rest = overlay:CreateTexture(nil, "ARTWORK", nil, 2)
        overlay:SetAllPoints(statusBar)
        overlay:SetScript("OnSizeChanged", function() mod.UpdateGameXPBar() end)
    elseif overlay:GetParent() ~= statusBar then   -- the game made a new bar
        overlay:SetParent(statusBar)
        overlay:ClearAllPoints()
        overlay:SetAllPoints(statusBar)
    end
    return overlay
end

function mod.UpdateGameXPBar()
    local statusBar, restFill
    if M.enabled and M.db.questXP and M.db.questXPGameBar then statusBar, restFill = GameXPStatusBar() end
    if not statusBar then
        if overlay then overlay:Hide() end
        return
    end
    local o = Overlay(statusBar)
    local cur, max = Num(UnitXP("player")), Num(UnitXPMax("player"))
    local w = o:GetWidth() or 0
    local xp = MMT.TurnInXP and tonumber(MMT.TurnInXP(MMT.PlayerFull() or "")) or 0
    if not cur or not max or max <= 0 or xp <= 0 or w <= 0 or AtMaxLevel() then
        o:Hide()
        return
    end
    local at = math.min(1, math.max(0, cur / max))
    local part = xp / max
    local over = at + part > 1
    if over then part = 1 - at end
    if part <= 0 then o:Hide() return end
    local r, g, b, a = Colour()
    o.shade:ClearAllPoints()
    o.shade:SetPoint("TOPLEFT", o, "TOPLEFT", w * at, 0)
    o.shade:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", w * at, 0)
    o.shade:SetWidth(math.max(1, w * part))
    o.shade:SetColorTexture(r, g, b, a)
    o.edge:SetColorTexture(r, g, b, 1)
    o.edge:SetShown(over)
    -- the smaller one on top: the shade lies over the game's rested fill, so when the
    -- quest XP is more than the rested XP, the rested part is drawn again over the shade
    local rested = Num(GetXPExhaustion and GetXPExhaustion()) or 0
    local restPart = math.min(rested / max, 1 - at)
    if rested > 0 and rested < xp and restPart > 0 and restFill then
        if o.restFill ~= restFill then
            LookLikeRested(o.rest, restFill)
            o.restFill = restFill
        end
        o.rest:ClearAllPoints()
        o.rest:SetPoint("TOPLEFT", o, "TOPLEFT", w * at, 0)
        o.rest:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", w * at, 0)
        o.rest:SetWidth(math.max(1, w * restPart))
        o.rest:Show()
    else
        o.rest:Hide()
    end
    o:Show()
end

---------------------------------------------------------------------------
-- Keeping it current (the sum itself is the core's: LevelUp.lua)
---------------------------------------------------------------------------
local function Refresh()
    mod.UpdateGameXPBar()
    if MMT.UpdateXPWindow then MMT.UpdateXPWindow() end
end

M:Listen("STATUS_CHANGED", function() mod.UpdateGameXPBar() end)   -- the turn-in XP changed, or a member's status
M:On("PLAYER_XP_UPDATE", function() mod.UpdateGameXPBar() end)
M:On("UPDATE_EXHAUSTION", function() mod.UpdateGameXPBar() end)
M:On("PLAYER_LEVEL_UP", function() C_Timer.After(1, mod.UpdateGameXPBar) end)
M:Listen("REFRESH", Refresh)   -- settings changed (also after a sync)

function mod.OnEnableQuestXP()
    C_Timer.After(4, Refresh)   -- after the core's first read of the quest log (3 s)
end

function mod.OnDisableQuestXP()
    if overlay then overlay:Hide() end
    if MMT.UpdateXPWindow then MMT.UpdateXPWindow() end
end

function mod.QuestXPReport()
    local bar = GameXPStatusBar()
    return ("quest XP: on=%s gameBar=%s turn-in XP=%s (core; per quest: \"-- Level up\" in /mmt debug dump)  game bar=%s overlay=%s"):format(
        tostring(M.db.questXP), tostring(M.db.questXPGameBar),
        tostring(MMT.TurnInXP and MMT.TurnInXP(MMT.PlayerFull() or "") or "no MMT.TurnInXP"),
        bar and (bar:GetName() or "found") or "not found", overlay and (overlay:IsVisible() and "visible" or "hidden") or "none")
end
