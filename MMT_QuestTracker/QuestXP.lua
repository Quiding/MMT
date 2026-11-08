-- MMT Quest Tracker: completed quest XP, shown like rested XP in a colour of its own.
-- The XP itself comes from the core (MMT 1.1.0+, LevelUp.lua): every client adds up
-- the reward XP of its quests that are ready to turn in and sends it with the
-- heartbeat ("qx"); MMT.TurnInXP(key) reads it for any member. This file only shows it
-- in the Info window as the piece "Completed quest XP" (Q 20%), which also shades
-- each member's bar right after the fill (core XPPieces.lua, bar = fn). The game's
-- own XP bar is left alone.
-- The shade stops at the end of the bar, with a bright edge there, when turning in
-- would reach the next level; the piece then shows more than 100%.

local _, mod = ...
local MMT = MMT
local M = mod.M

---------------------------------------------------------------------------
-- The XP of a member (the piece and the bars)
---------------------------------------------------------------------------
function mod.QuestXPOf(key, s)
    if not M.enabled then return 0 end   -- on / off: the piece itself (Info Window page)
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

local function Refresh()
    if MMT.UpdateXPWindow then MMT.UpdateXPWindow() end
end

MMT.RegisterXPPiece{
    id = "questxp", title = "Completed quest XP (%)", side = "RIGHT", on = true, before = "rep",
    sample = Hex(1, 0.8, 0.4) .. "Q 20%|r",
    tip = "XP of the quests ready to turn in, in percent of the current level, e.g. Q 20% (over 100%: enough for the next level). Also shaded on the bar after the XP, in its own colour (cogwheel). Switching the column off also removes the shade. The XP is added up by MMT on every character (needs MMT 1.1.0 or newer on teammates).",
    -- the cogwheel in "Column Visibility & Order": the only place for these settings
    options = {
        { "Color", "Colour on the bar",
            function() local r, g, b = Colour() return { r = r, g = g, b = b } end,
            function(c) M.db.questXPColour = { r = c.r, g = c.g, b = c.b } Refresh() end },
        { "Slider", "Opacity on the bar", 0.1, 1, 0.05,
            function() return M.db.questXPAlpha or 0.55 end,
            function(v) M.db.questXPAlpha = v Refresh() end, "%.2f" },
        { "Note", "The Q % text uses a lighter shade of the same colour." },
    },
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
-- Keeping it current (the sum itself is the core's: LevelUp.lua)
---------------------------------------------------------------------------

M:Listen("REFRESH", Refresh)   -- settings changed (also after a sync)

function mod.OnEnableQuestXP()
    C_Timer.After(4, Refresh)   -- after the core's first read of the quest log (3 s)
end

function mod.OnDisableQuestXP()
    Refresh()
end

function mod.QuestXPReport()
    return ("quest XP: piece on=%s turn-in XP=%s (core; per quest: \"-- Level up\" in /mmt debug dump)"):format(
        tostring(MMT.XPPieceOn and MMT.XPPieceOn("questxp")), tostring(MMT.TurnInXP and MMT.TurnInXP(MMT.PlayerFull() or "") or "no MMT.TurnInXP"))
end
