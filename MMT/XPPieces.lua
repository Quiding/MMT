-- MMT: the pieces of an Info window row (durability, bags, gold, the name, level, XP %, ...).
-- One order for the whole row, left to right, the name being a piece like the others:
-- ns.db.xp.pieces = { { id, on }, ... }. The bar lies behind the whole row.
-- Older profiles (pieces left of the bar / on it, "side") are converted once: the
-- left ones, the name, then the ones on the bar. Their old switches (showGold, ...)
-- are still kept up to date for clients without pieces.
-- Modules add their own pieces with MMT.RegisterXPPiece (CreateModules.md).

local _, ns = ...

ns.xpPieces = {}      -- [id] = def
ns.xpPieceIds = {}    -- registration order

-- def = { id, title, text = function(key, status) -> string | nil, on = shown by default
--         (modules: off unless set), sample = text while arranging when text() has nothing,
--         tip = settings tooltip, side = "LEFT": placed before the name when first added
--         (else after it), fixed = always shown (the name), icon = "START" | "END": where its
--         icon sits in the text (the "Line up the icons" choice aligns the column by it),
--         before = id: placed before that piece when first added (else by side),
--         hidden = function() -> true: the whole column is left out for now (e.g. no
--         pet out on the team) although it is switched on,
--         bar = function(key, status) -> XP: also shaded on the XP bar while the piece is on,
--         right after the fill (before rested XP), capped at the end of the bar,
--         barColour = function() -> r, g, b, a: the colour of that shade,
--         barTitle = its line in the row tooltip (else the title) }
-- text() may return a second value, true: the piece pulses (e.g. "LvlUp available")
function ns.RegisterXPPiece(def)
    assert(type(def) == "table" and type(def.id) == "string" and type(def.text) == "function",
        "MMT.RegisterXPPiece{ id = \"...\", title = \"...\", text = function(key, status) ... end }")
    if not ns.xpPieces[def.id] then ns.xpPieceIds[#ns.xpPieceIds + 1] = def.id end
    def.title = def.title or def.id
    def.side = (def.side == "LEFT") and "LEFT" or "RIGHT"
    ns.xpPieces[def.id] = def
    if ns.ready and ns.UpdateXPWindow then ns.UpdateXPWindow() end
end

-- colours while arranging and in the settings list: pieces blue, the name gold
ns.XP_PIECE_COLOUR = { 0.31, 0.70, 1.00 }
ns.XP_NAME_COLOUR = { 1.00, 0.82, 0.00 }
ns.XP_SIDE_COLOUR = { LEFT = ns.XP_PIECE_COLOUR, RIGHT = ns.XP_PIECE_COLOUR }   -- (old name)

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
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:1:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:1:0|t"

-- gold, silver, copper with icons; built here when the client has no coin string
local function FullCoins(copper)
    local text = ns.CoinText(copper)
    if text then return text end
    local g, sv, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = Thousands(g) .. GOLD_ICON end
    if sv > 0 or g > 0 then parts[#parts + 1] = sv .. SILVER_ICON end
    parts[#parts + 1] = c .. COPPER_ICON
    return table.concat(parts, " ")
end
-- (ns.LevelUpShowing: LevelUp.lua)
local LEVEL_UP = Hex(0.3, 1, 0.3) .. "LvlUp available|r"
local BAG_ICON = "|TInterface\\Icons\\INV_Misc_Bag_08:0:0:0:0:64:64:6:58:6:58|t"
local DUR_ICON = "|TInterface\\Icons\\Trade_BlackSmithing:0:0:0:0:64:64:6:58:6:58|t"

---------------------------------------------------------------------------
-- Built-in pieces
---------------------------------------------------------------------------
ns.RegisterXPPiece{ id = "gold", title = "Gold", side = "LEFT", on = true, sample = "123" .. GOLD_ICON, icon = "END",
    tip = "Gold of the character (format: Gold below).",
    text = function(_, s)
        if not s.money then return nil end
        if ns.db.xp.goldFormat == "FULL" then return FullCoins(math.floor(s.money)) end
        return Thousands(math.floor(s.money / 10000)) .. GOLD_ICON
    end }
ns.RegisterXPPiece{ id = "bags", title = "Free bag slots", side = "LEFT", on = true, sample = BAG_ICON .. " 12", icon = "START",
    text = function(_, s)
        if not s.free then return nil end
        local colour = (s.free == 0 and Hex(1, 0.3, 0.3)) or (s.free <= 4 and Hex(1, 0.85, 0.2)) or ""
        return BAG_ICON .. " " .. colour .. s.free .. (colour ~= "" and "|r" or "")
    end }
ns.RegisterXPPiece{ id = "durability", title = "Durability", side = "LEFT", on = true, sample = DUR_ICON .. " 100%", icon = "START",
    tip = "Lowest item or the average (Durability below).",
    text = function(_, s)
        local pct = (ns.db.xp.durability == "AVERAGE") and s.durAvg or s.durMin
        if pct then return DUR_ICON .. " " .. DurabilityColour(pct) .. pct .. "%|r" end
    end }
ns.RegisterXPPiece{ id = "level", title = "Level", side = "RIGHT", on = true, sample = "L60",
    text = function(_, s) return Hex(0.75, 0.75, 0.75) .. "L" .. s.level .. "|r" end }
ns.RegisterXPPiece{ id = "value", title = "Bar value (XP % or reputation)", side = "RIGHT", on = true, sample = "45.0%",
    tip = "What the bar shows (Bar shows): the XP in percent, or the standing with the watched faction.",
    text = function(key, s)
        if ns.db.xp.barMode == "REP" then return RepText(s) end
        if s.isMax or s.max <= 0 then return "max" end
        if ns.LevelUpShowing and ns.LevelUpShowing(key, s) then return LEVEL_UP, true end
        local text = ("%.1f%%"):format(s.cur / s.max * 100)
        if ns.XPGainFlashing and ns.XPGainFlashing(key) then return Hex(1, 0.85, 0.2) .. text .. "|r", true end
        return text
    end }
ns.RegisterXPPiece{ id = "rested", title = "Rested XP (%)", side = "RIGHT", on = true, sample = Hex(0.75, 0.6, 1) .. "R 35%|r",
    tip = "Rested XP in percent of the current level, e.g. R 35%. Also shaded on the bar.",
    text = function(key, s)
        if ns.db.xp.barMode == "REP" or s.isMax or s.max <= 0 then return nil end
        if ns.LevelUpShowing and ns.LevelUpShowing(key, s) then
            -- in the value's place when that piece is off
            if not ns.XPPieceOn("value") then return LEVEL_UP, true end
            return nil
        end
        if s.rested <= 0 then return nil end
        return Hex(0.75, 0.6, 1) .. ("R %d%%"):format(math.floor(s.rested / s.max * 100 + 0.5)) .. "|r"
    end }
ns.RegisterXPPiece{ id = "rep", title = "Reputation", side = "RIGHT", on = false, sample = "Friendly 40%",
    tip = "Standing with the watched faction, whatever the bar shows.",
    text = function(_, s) return RepText(s) end }
ns.RegisterXPPiece{ id = "layer", title = "Layer", side = "RIGHT", on = false, sample = "#3",
    text = function(_, s) return s.layer and (Hex(0.7, 0.7, 0.7) .. "#" .. s.layer .. "|r") or nil end }

-- the name: placed and filled by XPWindow.lua (crown, "(no follow)", Layer Hop)
ns.RegisterXPPiece{ id = "name", title = "Name", side = "RIGHT", on = true, fixed = true, sample = "Name",
    tip = "The character's name (with the leader crown and notes like \"no follow\"). Always shown; it takes the free space with the layout \"Name takes the free space\".",
    text = function() return nil end }

---------------------------------------------------------------------------
-- The saved order
---------------------------------------------------------------------------
-- the default order, left to right
local DEFAULT_ORDER = { "durability", "bags", "gold", "name", "level", "value", "rested", "rep", "pet", "mail", "layer" }
-- old switch of a built-in piece (kept in step for clients without pieces)
local SWITCH = { gold = "showGold", bags = "showBags", durability = "showDurability", level = "showLevel", rested = "showRested" }

local function Entry(id)
    local d = ns.xpPieces[id]
    local on = d.on and true or false
    local x = ns.db.xp
    if SWITCH[id] and x[SWITCH[id]] ~= nil then on = x[SWITCH[id]] and true or false end
    return { id = id, on = on }
end

function ns.XPPieceOrder()
    local x = ns.db.xp
    if type(x.pieces) ~= "table" then
        x.pieces = {}
        for _, id in ipairs(DEFAULT_ORDER) do
            if ns.xpPieces[id] then x.pieces[#x.pieces + 1] = Entry(id) end
        end
    end
    -- MMT 0.9.47: one order with the name; older lists had sides (left of the bar / on it)
    local hasName = false
    for _, p in ipairs(x.pieces) do if p.id == "name" then hasName = true end end
    if not hasName then
        local left, right = {}, {}
        for _, p in ipairs(x.pieces) do
            if p.side == "LEFT" then left[#left + 1] = p else right[#right + 1] = p end
        end
        -- the old default left order (gold, bags, durability) becomes the new one
        if #left == 3 and left[1].id == "gold" and left[2].id == "bags" and left[3].id == "durability" then
            left = { left[3], left[2], left[1] }
        end
        local list = {}
        for _, p in ipairs(left) do list[#list + 1] = p end
        list[#list + 1] = { id = "name", on = true }
        for _, p in ipairs(right) do list[#list + 1] = p end
        for _, p in ipairs(list) do p.side = nil end
        x.pieces = list
    end
    -- pieces registered since (new built-ins, modules): "LEFT" ones before the name, others at the end
    local have = {}
    for _, p in ipairs(x.pieces) do have[p.id] = true end
    for _, id in ipairs(ns.xpPieceIds) do
        if not have[id] then
            local e = Entry(id)
            local at = #x.pieces + 1
            local before = ns.xpPieces[id].before or (ns.xpPieces[id].side == "LEFT" and "name") or nil
            if before then
                for k, p in ipairs(x.pieces) do if p.id == before then at = k end end
            end
            table.insert(x.pieces, at, e)
        end
    end
    return x.pieces
end

-- back to the default order (pieces keep their on / off)
function ns.ResetXPPieceOrder()
    local on = {}
    for _, p in ipairs(ns.XPPieceOrder()) do on[p.id] = p.on end
    ns.db.xp.pieces = nil
    for _, p in ipairs(ns.XPPieceOrder()) do if on[p.id] ~= nil then p.on = on[p.id] end end
    ns.UpdateXPWindow()
end

local function Find(id)
    for i, p in ipairs(ns.XPPieceOrder()) do if p.id == id then return p, i end end
end

function ns.XPPieceOn(id)
    local p = Find(id)
    return p and p.on and ns.xpPieces[id] ~= nil or false
end

function ns.SetXPPiece(id, on)
    local p = Find(id)
    if not p then return end
    if ns.xpPieces[id] and ns.xpPieces[id].fixed then on = true end
    if on ~= nil then p.on = on and true or false end
    if SWITCH[id] then ns.db.xp[SWITCH[id]] = p.on end
    ns.UpdateXPWindow()
end

-- moves a piece before another one (nil: to the end); the side argument of
-- older callers is ignored: MoveXPPiece(id, side, beforeId)
function ns.MoveXPPiece(id, _, beforeId)
    local list = ns.XPPieceOrder()
    local p, i = Find(id)
    if not p or beforeId == id then return end
    table.remove(list, i)
    local at
    if beforeId then
        for j, q in ipairs(list) do if q.id == beforeId then at = j end end
    end
    table.insert(list, at or (#list + 1), p)
    ns.UpdateXPWindow()
end

-- the bar shades of a row (pieces with bar = fn, switched on), in piece order:
-- { { def, xp, r, g, b, a }, ... }, only those with XP > 0
function ns.XPBarPieces(key, s)
    local out = {}
    for _, p in ipairs(ns.XPPieceOrder()) do
        local d = p.on and ns.xpPieces[p.id]
        if d and d.bar then
            local ok, xp = pcall(d.bar, key, s)
            xp = ok and tonumber(xp) or 0
            if xp > 0 then
                local r, g, b, a = 1, 0.75, 0.2, 0.5
                if d.barColour then
                    local ok2, r2, g2, b2, a2 = pcall(d.barColour)
                    if ok2 and r2 then r, g, b, a = r2, g2, b2, a2 or a end
                end
                out[#out + 1] = { def = d, xp = xp, r = r, g = g, b = b, a = a }
            end
        end
    end
    return out
end

-- the shown pieces of a row, in order: { { id, def, text }, ... }; the name comes
-- with text = nil (XPWindow.lua fills it); arranging also lists pieces with nothing
-- to show (their sample)
function ns.XPRowPieces(key, s, arranging)
    local out = {}
    for _, p in ipairs(ns.XPPieceOrder()) do
        local d = (p.on or (ns.xpPieces[p.id] and ns.xpPieces[p.id].fixed)) and ns.xpPieces[p.id]
        if d and d.hidden and not arranging then
            local ok, hide = pcall(d.hidden)
            if ok and hide then d = nil end
        end
        if d then
            if p.id == "name" then
                out[#out + 1] = { id = "name", def = d, name = true }
            else
                local ok, text, pulse = pcall(d.text, key, s)
                if not ok or text == "" then text, pulse = nil, nil end
                if not text and arranging then text = Hex(0.5, 0.5, 0.5) .. (d.sample or d.title) .. "|r" end
                if text then out[#out + 1] = { id = p.id, def = d, text = text, pulse = pulse and not arranging or nil } end
            end
        end
    end
    return out
end
