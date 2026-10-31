-- MMT: the pieces of an XP window row (gold, bags, durability, level, XP %, ...).
-- Each one is shown or not, sits left of the bar or on it (right side), and has
-- its place in one order: ns.db.xp.pieces = { { id, side = "LEFT"|"RIGHT", on }, ... }.
-- Older profiles get that list from their old switches (showGold, showLevel, ...),
-- which are still kept up to date for clients without pieces.
-- Modules add their own pieces with MMT.RegisterXPPiece (CreateModules.md).

local _, ns = ...

ns.xpPieces = {}      -- [id] = def
ns.xpPieceIds = {}    -- registration order

-- def = { id, title, side = "LEFT" | "RIGHT", text = function(key, status) -> string | nil,
--         on = shown by default (modules: off unless set), sample = text while arranging when
--         text() has nothing, tip = settings tooltip }
function ns.RegisterXPPiece(def)
    assert(type(def) == "table" and type(def.id) == "string" and type(def.text) == "function",
        "MMT.RegisterXPPiece{ id = \"...\", title = \"...\", text = function(key, status) ... end }")
    if not ns.xpPieces[def.id] then ns.xpPieceIds[#ns.xpPieceIds + 1] = def.id end
    def.title = def.title or def.id
    def.side = (def.side == "LEFT") and "LEFT" or "RIGHT"
    ns.xpPieces[def.id] = def
    if ns.ready and ns.UpdateXPWindow then ns.UpdateXPWindow() end
end

-- colour of each side (settings list, pieces while arranging): left column blue, bar gold
ns.XP_SIDE_COLOUR = { LEFT = { 0.31, 0.70, 1.00 }, RIGHT = { 1.00, 0.82, 0.00 } }

---------------------------------------------------------------------------
-- Text helpers (also used by XPWindow.lua)
---------------------------------------------------------------------------
local function Hex(r, g, b)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end
ns.XPHex = Hex

local function Thousands(n)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local function DurabilityColour(pct)
    if pct >= 60 then return Hex(0.4, 1, 0.4) elseif pct >= 25 then return Hex(1, 0.85, 0.2) end
    return Hex(1, 0.3, 0.3)
end

local function StandingLabel(standing)
    return _G["FACTION_STANDING_LABEL" .. tostring(standing)] or ("Standing " .. tostring(standing))
end

function ns.XPRepColour(standing)
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing]
    if c then return c.r, c.g, c.b end
    return 0.3, 0.7, 0.3
end

local function RepText(s)
    local r = s.rep
    if not r then return Hex(0.5, 0.5, 0.5) .. "no faction|r" end
    local cr, cg, cb = ns.XPRepColour(r.standing)
    local text = StandingLabel(r.standing)
    if (r.max or 0) > 0 then text = text .. (" %d%%"):format(math.floor(r.cur / r.max * 100)) end
    return Hex(cr, cg, cb) .. text .. "|r"
end

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:1:0|t"
local BAG_ICON = "|TInterface\\Icons\\INV_Misc_Bag_08:0:0:0:0:64:64:6:58:6:58|t"
local DUR_ICON = "|TInterface\\Icons\\Trade_BlackSmithing:0:0:0:0:64:64:6:58:6:58|t"

---------------------------------------------------------------------------
-- Built-in pieces, in the window's old order
---------------------------------------------------------------------------
ns.RegisterXPPiece{ id = "gold", title = "Gold", side = "LEFT", on = true, sample = "123" .. GOLD_ICON,
    tip = "Gold of the character (format: Gold below).",
    text = function(_, s)
        if not s.money then return nil end
        if ns.db.xp.goldFormat == "FULL" then
            local text = ns.CoinText(s.money)
            if text then return text end
        end
        return Thousands(math.floor(s.money / 10000)) .. GOLD_ICON
    end }
ns.RegisterXPPiece{ id = "bags", title = "Free bag slots", side = "LEFT", on = true, sample = BAG_ICON .. " 12",
    text = function(_, s)
        if not s.free then return nil end
        local colour = (s.free == 0 and Hex(1, 0.3, 0.3)) or (s.free <= 4 and Hex(1, 0.85, 0.2)) or ""
        return BAG_ICON .. " " .. colour .. s.free .. (colour ~= "" and "|r" or "")
    end }
ns.RegisterXPPiece{ id = "durability", title = "Durability", side = "LEFT", on = true, sample = DUR_ICON .. " 100%",
    tip = "Lowest item or the average (Durability below).",
    text = function(_, s)
        local pct = (ns.db.xp.durability == "AVERAGE") and s.durAvg or s.durMin
        if pct then return DUR_ICON .. " " .. DurabilityColour(pct) .. pct .. "%|r" end
    end }
ns.RegisterXPPiece{ id = "level", title = "Level", side = "RIGHT", on = true, sample = "L60",
    text = function(_, s) return Hex(0.75, 0.75, 0.75) .. "L" .. s.level .. "|r" end }
ns.RegisterXPPiece{ id = "value", title = "Bar value (XP % or reputation)", side = "RIGHT", on = true, sample = "45.0%",
    tip = "What the bar shows (Bar shows): the XP in percent, or the standing with the watched faction.",
    text = function(_, s)
        if ns.db.xp.barMode == "REP" then return RepText(s) end
        if s.isMax or s.max <= 0 then return "max" end
        return ("%.1f%%"):format(s.cur / s.max * 100)
    end }
ns.RegisterXPPiece{ id = "rested", title = "Rested XP (%)", side = "RIGHT", on = true, sample = Hex(0.75, 0.6, 1) .. "R 35%|r",
    tip = "Rested XP in percent of the current level, e.g. R 35%. Also shaded on the bar.",
    text = function(_, s)
        if ns.db.xp.barMode == "REP" or s.isMax or s.max <= 0 or s.rested <= 0 then return nil end
        return Hex(0.75, 0.6, 1) .. ("R %d%%"):format(math.floor(s.rested / s.max * 100 + 0.5)) .. "|r"
    end }
ns.RegisterXPPiece{ id = "rep", title = "Reputation", side = "RIGHT", on = false, sample = "Friendly 40%",
    tip = "Standing with the watched faction, whatever the bar shows.",
    text = function(_, s) return RepText(s) end }
ns.RegisterXPPiece{ id = "layer", title = "Layer", side = "RIGHT", on = false, sample = "#3",
    text = function(_, s) return s.layer and (Hex(0.7, 0.7, 0.7) .. "#" .. s.layer .. "|r") or nil end }

---------------------------------------------------------------------------
-- The saved order
---------------------------------------------------------------------------
-- old switch of a built-in piece (kept in step for clients without pieces)
local SWITCH = { gold = "showGold", bags = "showBags", durability = "showDurability", level = "showLevel", rested = "showRested" }

function ns.XPPieceOrder()
    local x = ns.db.xp
    if type(x.pieces) ~= "table" then
        x.pieces = {}
        for _, id in ipairs(ns.xpPieceIds) do
            local d = ns.xpPieces[id]
            local on = d.on
            if SWITCH[id] and x[SWITCH[id]] ~= nil then on = x[SWITCH[id]] end
            x.pieces[#x.pieces + 1] = { id = id, side = d.side, on = on and true or false }
        end
    end
    -- pieces registered since (new built-ins, modules): at the end, with their default
    local have = {}
    for _, p in ipairs(x.pieces) do have[p.id] = true end
    for _, id in ipairs(ns.xpPieceIds) do
        if not have[id] then
            local d = ns.xpPieces[id]
            x.pieces[#x.pieces + 1] = { id = id, side = d.side, on = d.on and true or false }
        end
    end
    return x.pieces
end

local function Find(id)
    for i, p in ipairs(ns.XPPieceOrder()) do if p.id == id then return p, i end end
end

function ns.XPPieceOn(id)
    local p = Find(id)
    return p and p.on and ns.xpPieces[id] ~= nil or false
end

function ns.SetXPPiece(id, on, side)
    local p = Find(id)
    if not p then return end
    if on ~= nil then p.on = on and true or false end
    if side then p.side = side end
    if SWITCH[id] then ns.db.xp[SWITCH[id]] = p.on end
    ns.UpdateXPWindow()
end

-- moves a piece to a side, before another piece (nil: after the side's last one)
function ns.MoveXPPiece(id, side, beforeId)
    local list = ns.XPPieceOrder()
    local p, i = Find(id)
    if not p or beforeId == id then return end
    table.remove(list, i)
    p.side = side or p.side
    local at
    if beforeId then
        for j, q in ipairs(list) do if q.id == beforeId then at = j end end
    else
        for j, q in ipairs(list) do if q.side == p.side then at = j + 1 end end
    end
    table.insert(list, at or (#list + 1), p)
    ns.UpdateXPWindow()
end

-- shown pieces of one side, in order: { { id, def, text }, ... }; arranging also lists
-- pieces with nothing to show (their sample)
function ns.XPPiecesOf(side, key, s, arranging)
    local out = {}
    for _, p in ipairs(ns.XPPieceOrder()) do
        local d = p.on and p.side == side and ns.xpPieces[p.id]
        if d then
            local ok, text = pcall(d.text, key, s)
            if not ok or text == "" then text = nil end
            if not text and arranging then text = Hex(0.5, 0.5, 0.5) .. (d.sample or d.title) .. "|r" end
            if text then out[#out + 1] = { id = p.id, def = d, text = text } end
        end
    end
    return out
end
