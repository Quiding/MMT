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
--         barTitle = its line in the row tooltip (no line without),
--         options = { { kind, ... }, ... }: settings of the piece, shown in a small popup
--         behind a cogwheel in its row of "Column Visibility & Order". kind is a method
--         of UI.Column ("Color", "Slider", "Check", "Cycle", "Note", "Space"), the rest
--         its arguments as usual, e.g. { "Color", "Colour", get, set } }
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
    local x = ns.db.xp
    if pct >= (x.durWarn or 60) then return Hex(0.4, 1, 0.4) elseif pct >= (x.durBad or 25) then return Hex(1, 0.85, 0.2) end
    return Hex(1, 0.3, 0.3)
end

-- settings behind the cogwheels (def.options): a setting of ns.db.xp, the window redrawn
local function XOpt(key, default)
    return function() local v = ns.db.xp[key] if v == nil then return default end return v end,
           function(v) ns.db.xp[key] = v if ns.UpdateXPWindow then ns.UpdateXPWindow() end end
end
local function XColour(key, dr, dg, db)
    return function() local c = ns.db.xp[key] or {} return { r = c.r or dr, g = c.g or dg, b = c.b or db } end,
           function(c) ns.db.xp[key] = { r = c.r, g = c.g, b = c.b } if ns.UpdateXPWindow then ns.UpdateXPWindow() end end
end
-- options entry: { kind, text, <getter, setter>, ... }
local function O(kind, text, get, set, ...) return { kind, text, get, set, ... } end
local function OCycle(text, choices, get, set) return { "Cycle", text, choices, get, set } end
local function OCheck(text, key, default, tip)
    local get, set = XOpt(key, default)
    return { "Check", text, get, set, tip }
end
local function OSlider(text, min, max, step, get, set, fmt) return { "Slider", text, min, max, step, get, set, fmt } end

-- the XP fill without class colours
function ns.XPBarColour()
    local c = ns.db.xp.barColour or {}
    return c.r or 0.31, c.g or 0.70, c.b or 1.00
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
    tip = "Gold of the character (format: cogwheel).",
    options = {
        OCycle("Show as", { { value = "GOLD", text = "Gold only" }, { value = "FULL", text = "Gold, silver, copper" } },
            XOpt("goldFormat", "GOLD")),
    },
    text = function(_, s)
        if not s.money then return nil end
        if ns.db.xp.goldFormat == "FULL" then return FullCoins(math.floor(s.money)) end
        return Thousands(math.floor(s.money / 10000)) .. GOLD_ICON
    end }
ns.RegisterXPPiece{ id = "bags", title = "Free bag slots", side = "LEFT", on = true, sample = BAG_ICON .. " 12", icon = "START",
    options = {
        OSlider("Yellow at or below (slots)", 0, 30, 1, XOpt("bagWarn", 4)),
        OSlider("Red at or below (slots)", 0, 30, 1, XOpt("bagBad", 0)),
    },
    text = function(_, s)
        if not s.free then return nil end
        local x = ns.db.xp
        local colour = (s.free <= (x.bagBad or 0) and Hex(1, 0.3, 0.3)) or (s.free <= (x.bagWarn or 4) and Hex(1, 0.85, 0.2)) or ""
        return BAG_ICON .. " " .. colour .. s.free .. (colour ~= "" and "|r" or "")
    end }
ns.RegisterXPPiece{ id = "durability", title = "Durability", side = "LEFT", on = true, sample = DUR_ICON .. " 100%", icon = "START",
    tip = "Lowest item or the average (cogwheel).",
    options = {
        OCycle("Show as", { { value = "LOWEST", text = "Lowest item" }, { value = "AVERAGE", text = "Average of all items" } },
            XOpt("durability", "LOWEST")),
        OSlider("Yellow below (%)", 5, 100, 5, XOpt("durWarn", 60)),
        OSlider("Red below (%)", 0, 95, 5, XOpt("durBad", 25)),
    },
    text = function(_, s)
        local pct = (ns.db.xp.durability == "AVERAGE") and s.durAvg or s.durMin
        if pct then return DUR_ICON .. " " .. DurabilityColour(pct) .. pct .. "%|r" end
    end }
ns.RegisterXPPiece{ id = "level", title = "Level", side = "RIGHT", on = true, sample = "L60",
    options = { O("Check", "Show \"L\" in front (L60)", XOpt("levelPrefix", true)) },
    text = function(_, s)
        return Hex(0.75, 0.75, 0.75) .. (ns.db.xp.levelPrefix == false and "" or "L") .. s.level .. "|r"
    end }
ns.RegisterXPPiece{ id = "value", title = "Bar value (XP % or reputation)", side = "RIGHT", on = true, sample = "45.0%",
    tip = "What the bar shows (Bar shows): the XP in percent, or the standing with the watched faction.",
    options = {
        OCycle("Decimals of the XP %", { { value = 0, text = "45%" }, { value = 1, text = "45.0%" }, { value = 2, text = "45.03%" } },
            XOpt("valueDecimals", 1)),
        O("Color", "Bar colour without class colors", XColour("barColour", 0.31, 0.70, 1.00)),
        OCheck("Highlight when I can level up", "levelUpHint", true,
            "A pulsing \"LvlUp available\" in place of the XP when turning in the quests that are ready would reach the next level."),
        OCheck("Highlight big XP gains", "xpFlash", true,
            "The XP bar and the XP value light up when a character gets at least 3% of the level's XP at once (e.g. from quest turn-ins)."),
        { "Note", "Class colors and what the bars show (XP or reputation): Basics." },
    },
    text = function(key, s)
        if ns.db.xp.barMode == "REP" then return RepText(s) end
        if s.isMax or s.max <= 0 then return "max" end
        if ns.LevelUpShowing and ns.LevelUpShowing(key, s) then return LEVEL_UP, true end
        local text = ("%." .. (tonumber(ns.db.xp.valueDecimals) or 1) .. "f%%"):format(s.cur / s.max * 100)
        if ns.XPGainFlashing and ns.XPGainFlashing(key) then return Hex(1, 0.85, 0.2) .. text .. "|r", true end
        return text
    end }
-- the rested colour (cogwheel of the piece): the bar's shade, and lighter for the text
function ns.XPRestedColour()
    local c = ns.db.xp.restedColour or {}
    return c.r or 0.65, c.g or 0.45, c.b or 1.0, ns.db.xp.restedAlpha or 0.30
end
function ns.XPRestedTextColour()
    local r, g, b = ns.XPRestedColour()
    return 0.35 + r * 0.65, 0.35 + g * 0.65, 0.35 + b * 0.65
end
local function RestedOptions()
    return {
        { "Color", "Colour on the bar",
            function() local r, g, b = ns.XPRestedColour() return { r = r, g = g, b = b } end,
            function(c) ns.db.xp.restedColour = { r = c.r, g = c.g, b = c.b } ns.UpdateXPWindow() end },
        { "Slider", "Opacity on the bar", 0.05, 1, 0.05,
            function() return ns.db.xp.restedAlpha or 0.30 end,
            function(v) ns.db.xp.restedAlpha = v ns.UpdateXPWindow() end, "%.2f" },
        { "Note", "The R % text uses a lighter shade of the same colour." },
    }
end

ns.RegisterXPPiece{ id = "rested", title = "Rested XP (%)", side = "RIGHT", on = true, sample = Hex(0.75, 0.6, 1) .. "R 35%|r",
    tip = "Rested XP in percent of the current level, e.g. R 35%. Also shaded on the bar.",
    options = RestedOptions(),
    text = function(key, s)
        if ns.db.xp.barMode == "REP" or s.isMax or s.max <= 0 then return nil end
        if ns.LevelUpShowing and ns.LevelUpShowing(key, s) then
            -- in the value's place when that piece is off
            if not ns.XPPieceOn("value") then return LEVEL_UP, true end
            return nil
        end
        if s.rested <= 0 then return nil end
        return Hex(ns.XPRestedTextColour()) .. ("R %d%%"):format(math.floor(s.rested / s.max * 100 + 0.5)) .. "|r"
    end }
-- Watch a faction (by name) on the reputation bar: the cogwheel's "Watch it on every
-- character". Headers are expanded so a faction under a collapsed one is found too.
function ns.WatchFactionNamed(name)
    if type(name) ~= "string" or name == "" then return false end
    local CR = C_Reputation
    if CR and CR.GetNumFactions and CR.GetFactionDataByIndex and CR.SetWatchedFactionByIndex then
        if CR.ExpandAllFactionHeaders then pcall(CR.ExpandAllFactionHeaders) end
        for i = 1, (tonumber(CR.GetNumFactions()) or 0) do
            local ok, d = pcall(CR.GetFactionDataByIndex, i)
            if ok and type(d) == "table" and d.name == name and (not d.isHeader or d.isHeaderWithRep) then
                return (pcall(CR.SetWatchedFactionByIndex, i))
            end
        end
        return false
    end
    if GetNumFactions and GetFactionInfo and SetWatchedFactionIndex then
        if ExpandAllFactionHeaders then pcall(ExpandAllFactionHeaders) end
        for i = 1, (GetNumFactions() or 0) do
            local n, _, _, _, _, _, _, _, isHeader, _, hasRep = GetFactionInfo(i)
            if n == name and (not isHeader or hasRep) then
                return (pcall(SetWatchedFactionIndex, i))
            end
        end
    end
    return false
end

-- this character's watched faction on every team character
function ns.WatchFactionOnTeam()
    local r = ns.WatchedFaction and ns.WatchedFaction()
    if not r or not r.name then
        ns.Print("Watch a faction on the reputation bar first (Reputation tab: \"Show as Experience Bar\").")
        return
    end
    ns.SendToTeam("REPW:" .. r.name, true, "ALERT")
    ns.Print("Asked the team to watch %s.", r.name)
end
ns.Listen("TEAM_MESSAGE", function(key, sender, text)
    local name = text:match("^REPW:(.+)$")
    if not name then return end
    if ns.WatchFactionNamed(name) then
        C_Timer.After(0.5, function() if ns.BroadcastXP then ns.BroadcastXP(true) end end)
    else
        ns.Print("%s asked to watch %s, but this character doesn't know that faction.", ns.FullDisplay(key), name)
    end
end)

ns.RegisterXPPiece{ id = "rep", title = "Reputation", side = "RIGHT", on = false, sample = "Friendly 40%",
    tip = "Standing with the watched faction, whatever the bar shows.",
    options = {
        { "Button", "Watch my faction on every character", function() ns.WatchFactionOnTeam() end },
        { "Note", "Every team character then shows the faction this character watches on its reputation bar, so this column (and \"Bars show: Reputation\") compares the same faction." },
    },
    text = function(_, s) return RepText(s) end }
ns.RegisterXPPiece{ id = "layer", title = "Layer", side = "RIGHT", on = false, sample = "#3",
    options = { O("Check", "Orange when not on your layer", XOpt("layerMark", false)) },
    text = function(_, s)
        if not s.layer then return nil end
        local me = ns.status[ns.PlayerFull() or ""]
        if ns.db.xp.layerMark and me and me.layer and me.layer ~= s.layer then
            return Hex(1, 0.6, 0.2) .. "#" .. s.layer .. "|r"
        end
        return Hex(0.7, 0.7, 0.7) .. "#" .. s.layer .. "|r"
    end }

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
