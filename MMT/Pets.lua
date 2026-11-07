-- MMT: hunter pets in the XP window. Every hunter's client sends whether a pet
-- is out and its happiness and loyalty with the heartbeat ("pt=<happiness>.<loyalty>",
-- "pt=0" without a pet), and right away when that changes (pet summoned or
-- dismissed, happiness changed). The XP window piece "Pet happiness & loyalty"
-- (off by default) shows them as icons, "-" for characters that aren't hunters;
-- the column hides while no hunter of the team has a pet out and comes back as
-- soon as one is summoned. The row tooltip shows the last known values
-- (MMTDB.petLast[team key] = { h, l, t }).

local _, ns = ...

-- happiness: 1 unhappy, 2 content, 3 happy (the game's pet frame icons)
local HAPPY_TEX = "Interface\\PetPaperDollFrame\\UI-PetHappiness"
local HAPPY_X = { [3] = "0:24", [2] = "24:48", [1] = "48:72" }
local HAPPY_TEXT = { [3] = "Happy", [2] = "Content", [1] = "Unhappy" }
local HAPPY_COLOUR = { [3] = { 0.4, 1, 0.4 }, [2] = { 1, 0.85, 0.2 }, [1] = { 1, 0.3, 0.3 } }
local LOYALTY_ICON = "|TInterface\\Icons\\Ability_Hunter_BeastTraining:0:0:0:0:64:64:6:58:6:58|t"

local function HappyIcon(h)
    local x = HAPPY_X[h]
    return x and ("|T%s:0:0:0:0:128:64:%s:0:23|t"):format(HAPPY_TEX, x) or ""
end

local function IsHunter(class) return class == "HUNTER" end

-- this character's pet: nil (no hunter), false (no pet out) or { h, l }
local function OwnPet()
    local _, class = UnitClass("player")
    if not IsHunter(class) then return nil end
    if not UnitExists("pet") then return false end
    local h = GetPetHappiness and tonumber((ns.Safe(GetPetHappiness))) or nil
    local l
    if GetPetLoyalty then
        local text = ns.Safe(GetPetLoyalty)
        l = type(text) == "string" and tonumber(text:match("(%d+)")) or tonumber(text)
    end
    return { h = h, l = l }
end

local function Encode(p)
    if p == nil then return nil end
    if p == false then return "0" end
    return ("%d.%d"):format(p.h or 0, p.l or 0)
end
local function Decode(v)
    if not v or v == "" then return nil end
    if v == "0" then return false end
    local h, l = v:match("^(%d+)%.(%d+)$")
    h, l = tonumber(h), tonumber(l)
    return { h = (h and h > 0) and h or nil, l = (l and l > 0) and l or nil }
end


local function Last()
    MMTDB.petLast = MMTDB.petLast or {}
    return MMTDB.petLast
end

-- a member's pet: nil (not a hunter / unknown), false (no pet out) or { h, l }
function ns.PetOf(key)
    local p
    if ns.IsSelf(key) then
        p = OwnPet()
    else
        local s = ns.status[key]
        if not (s and s.online ~= false and IsHunter(s.class)) then return nil end
        p = Decode(s.ext and s.ext.pt)
    end
    if p then Last()[key] = { h = p.h, l = p.l, t = time() } end
    return p
end

-- any hunter of the team (shown in the window) with a pet out?
function ns.AnyPetOut()
    local me = ns.PlayerFull()
    if me and ns.PetOf(me) then return true end
    for _, key in ipairs(ns.SortedMembers()) do
        if not ns.IsSelf(key) and ns.IsOnline(key) and ns.PetOf(key) then return true end
    end
    return false
end

local function ClassOf(key, s)
    if ns.IsSelf(key) then return select(2, UnitClass("player")) end
    local m = ns.db.team[key]
    return (s and s.class) or (m and m.class)
end

ns.RegisterXPPiece{ id = "pet", title = "Pet happiness & loyalty", side = "RIGHT", on = false, before = "layer",
    icon = "START", sample = HappyIcon(3) .. " " .. LOYALTY_ICON .. "6",
    tip = "Hunters: the pet's happiness and loyalty level as icons; \"-\" for characters that aren't hunters. Hidden while no hunter of the team has a pet out (the row tooltip keeps the last known values).",
    hidden = function() return not ns.AnyPetOut() end,
    text = function(key, s)
        if not IsHunter(ClassOf(key, s)) then return ns.XPHex(0.5, 0.5, 0.5) .. "-|r" end
        local p = ns.PetOf(key)
        if not p then return ns.XPHex(0.5, 0.5, 0.5) .. "no pet|r" end
        return HappyIcon(p.h) .. (p.l and (" " .. LOYALTY_ICON .. p.l) or "")
    end }

-- the row tooltip (XPWindow.lua): happiness and loyalty, or the last known ones
function ns.PetTooltip(tip, key)
    local s = ns.status[key]
    if not IsHunter(ClassOf(key, s)) then return end
    local p = ns.PetOf(key)
    local last = Last()[key]
    local shown = p or last
    if not shown then
        tip:AddDoubleLine("Pet", "no pet seen yet", 1, 1, 1, 0.6, 0.6, 0.6)
        return
    end
    local c = HAPPY_COLOUR[shown.h] or { 0.8, 0.8, 0.8 }
    local text = (HAPPY_TEXT[shown.h] or "happiness unknown") .. (shown.l and (", loyalty level %d"):format(shown.l) or "")
    if not p then
        text = text .. (" (last known%s)"):format(last.t and (", " .. ns.Ago(last.t)) or "")
        c = { 0.6, 0.6, 0.6 }
    end
    tip:AddDoubleLine(p and "Pet" or "Pet (none out)", HappyIcon(shown.h) .. " " .. text, 1, 1, 1, c[1], c[2], c[3])
end

-- pet summoned / dismissed / happiness or loyalty changed: tell the team now.
-- The game fires these events very often (in combat about every second), so
-- only a real change of what is sent goes out, and at most every 10 seconds;
-- the regular heartbeat carries it otherwise.
local lastSent, lastAt, pending = nil, 0, false
local function SendIfChanged()
    pending = false
    if not ns.ready then return end
    local v = Encode(OwnPet())
    if v == lastSent then return end
    local wait = 10 - (GetTime() - lastAt)
    if wait > 0 then
        pending = true
        C_Timer.After(wait, SendIfChanged)
        return
    end
    lastSent, lastAt = v, GetTime()
    ns.BroadcastXP(true)
end
local function Changed()
    if pending then return end
    pending = true
    C_Timer.After(1, SendIfChanged)
end
ns.On("UNIT_PET", function(unit) if unit == "player" then Changed() end end)
ns.On("UNIT_HAPPINESS", function(unit) if unit == nil or unit == "pet" then Changed() end end)
ns.On("PET_UI_UPDATE", Changed)
-- the heartbeat sent it too: that counts as told
ns.CoreHeartbeat("pt", function() local v = Encode(OwnPet()) lastSent = v return v end)
