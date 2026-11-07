-- MMT: hunter pets in the Info window. Every hunter's client sends whether a pet
-- is out and its happiness and loyalty with the heartbeat ("pt=<happiness>.<loyalty>",
-- "pt=0" without a pet), and right away when that changes (pet summoned or
-- dismissed, happiness changed). The Info window piece "Pet happiness & loyalty"
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

-- WoW: Forever has no GetPetHappiness / GetPetLoyalty and keeps the pet's
-- happiness power secret. Sources, in this order:
--   1. GetPetHappiness() / GetPetLoyalty(), also inside a C_ table (found once)
--   2. the happiness icon of the game's pet frame (its texture coordinates:
--      happy, content, unhappy side by side, as in UI-PetHappiness)
--   3. the pet's happiness power, when it is readable (0 .. max in thirds)
local HAPPINESS_POWER = (Enum and Enum.PowerType and Enum.PowerType.Happiness) or 4

local found
local function FindApis()
    if found then return found end
    found = { happy = GetPetHappiness, loyal = GetPetLoyalty }
    for name, t in pairs(_G) do
        if type(name) == "string" and name:sub(1, 2) == "C_" and type(t) == "table" then
            for k, fn in pairs(t) do
                if type(fn) == "function" and type(k) == "string" then
                    if not found.happy and (k == "GetPetHappiness" or k == "GetHappiness") then
                        found.happy, found.happyName = fn, name .. "." .. k
                    elseif not found.loyal and (k == "GetPetLoyalty" or k == "GetLoyalty" or k == "GetPetDependability") then
                        found.loyal, found.loyalName = fn, name .. "." .. k
                    end
                end
            end
        end
    end
    found.happyName = found.happyName or (GetPetHappiness and "GetPetHappiness")
    found.loyalName = found.loyalName or (GetPetLoyalty and "GetPetLoyalty")
    return found
end

-- the pet frame's happiness icon: { texture, frame } or nil
local function HappinessIcon()
    local tex = _G.PetFrameHappinessTexture
    local frame = _G.PetFrameHappiness
    if not tex and frame and frame.GetRegions then
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetTexCoord then tex = r break end
        end
    end
    if not tex and _G.PetFrame and _G.PetFrame.Happiness then
        frame = _G.PetFrame.Happiness
        tex = frame.Texture or frame.Icon or (frame.GetTexCoord and frame)
    end
    return tex, frame
end

local function IconHappiness()
    local tex, frame = HappinessIcon()
    if not (tex and tex.GetTexCoord) then return nil end
    if frame and frame.IsShown and not frame:IsShown() then return nil end
    local ok, left = pcall(tex.GetTexCoord, tex)
    left = ok and tonumber(left) or nil
    if not left or ns.IsSecret(left) then return nil end
    -- 0 .. 0.1875 happy, .. 0.375 content, .. 0.5625 unhappy
    if left < 0.1 then return 3 elseif left < 0.28 then return 2 elseif left < 0.47 then return 1 end
    return nil
end

local function ReadHappiness()
    local api = FindApis()
    if api.happy then
        local h = tonumber((ns.Safe(api.happy)))
        if h and h >= 1 and h <= 3 then return h, api.happyName end
    end
    local h = IconHappiness()
    if h then return h, "pet frame icon" end
    if UnitPower and UnitPowerMax then
        local cur = tonumber((ns.Safe(UnitPower, "pet", HAPPINESS_POWER)))
        local max = tonumber((ns.Safe(UnitPowerMax, "pet", HAPPINESS_POWER)))
        if cur and max and max > 0 then
            local r = cur / max
            return (r >= 2 / 3 and 3) or (r >= 1 / 3 and 2) or 1, "UnitPower"
        end
    end
    return nil, "none"
end

-- loyalty level ("Loyalty Level 3", "Submissive 3", or a number)
local function ReadLoyalty()
    local api = FindApis()
    if not api.loyal then return nil end
    local a, b = ns.Safe(api.loyal)
    for _, v in ipairs({ a, b }) do
        if type(v) == "number" then return v end
        if type(v) == "string" and v:match("%d+") then return tonumber(v:match("(%d+)")) end
    end
    return nil
end

-- this character's pet: nil (no hunter), false (no pet out) or { h, l }
local function OwnPet()
    local _, class = UnitClass("player")
    if not IsHunter(class) then return nil end
    if not UnitExists("pet") then return false end
    return { h = (ReadHappiness()), l = ReadLoyalty() }
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
        if not p.h and not p.l then return ns.XPHex(0.5, 0.5, 0.5) .. "?|r" end
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
ns.On("UNIT_POWER_UPDATE", function(unit) if unit == "pet" then Changed() end end)
-- the heartbeat sent it too: that counts as told
ns.CoreHeartbeat("pt", function() local v = Encode(OwnPet()) lastSent = v return v end)

-- /mmt debug dump: what this client can read about its pet, and what the team sent
function ns.PetReport(add)
    local _, class = UnitClass("player")
    local h, src = ReadHappiness()
    local api = FindApis()
    add(("-- Pet  class=%s pet=%s name=%s"):format(tostring(class), tostring(UnitExists("pet")), tostring(ns.Safe(UnitName, "pet"))))
    add(("  read: happiness=%s (from %s) loyalty=%s (from %s)  sent pt=%s"):format(tostring(h), src,
        tostring(ReadLoyalty()), tostring(api.loyalName), tostring(Encode(OwnPet()))))
    -- the power: secret or not
    if UnitPower then
        local ok, cur = pcall(UnitPower, "pet", HAPPINESS_POWER)
        add(("  UnitPower(pet,%s): ok=%s secret=%s value=%s max=%s"):format(tostring(HAPPINESS_POWER), tostring(ok),
            tostring(ok and ns.IsSecret(cur)), ok and not ns.IsSecret(cur) and tostring(cur) or "-",
            tostring(UnitPowerMax and ns.Safe(UnitPowerMax, "pet", HAPPINESS_POWER))))
    end
    -- the pet frame's icon
    local tex, frame = HappinessIcon()
    local coords = "-"
    if tex and tex.GetTexCoord then
        local ok, a, b, c, d = pcall(tex.GetTexCoord, tex)
        coords = ok and (tostring(a) .. "," .. tostring(b) .. "," .. tostring(c) .. "," .. tostring(d)) or "error"
    end
    add(("  pet frame icon: frame=%s shown=%s texture=%s file=%s coords=%s"):format(
        tostring(frame and (frame.GetName and frame:GetName() or "yes")), tostring(frame and frame.IsShown and frame:IsShown()),
        tostring(tex and (tex.GetName and tex:GetName() or "yes")),
        tostring(tex and tex.GetTexture and select(2, pcall(tex.GetTexture, tex))), coords))
    -- every global / C_ function that sounds like it
    local names = {}
    local function Match(k) return k:find("[Hh]appiness") or k:find("[Ll]oyalty") or k:find("[Dd]ependab") end
    for k, v in pairs(_G) do
        if type(k) == "string" then
            if type(v) == "function" and Match(k) then names[#names + 1] = k
            elseif type(v) == "table" and k:sub(1, 2) == "C_" then
                for k2, v2 in pairs(v) do
                    if type(k2) == "string" and type(v2) == "function" and Match(k2) then names[#names + 1] = k .. "." .. k2 end
                end
            end
        end
    end
    table.sort(names)
    add("  functions: " .. (#names > 0 and table.concat(names, ", ") or "none"))
    local frames = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "table" and Match(k) and #frames < 15 then frames[#frames + 1] = k end
    end
    table.sort(frames)
    add("  globals: " .. (#frames > 0 and table.concat(frames, ", ") or "none"))
    for _, key in ipairs(ns.SortedMembers()) do
        local s = ns.status[key]
        if not ns.IsSelf(key) and s and IsHunter(s.class) then
            add(("  %s pt=%s"):format(ns.Repr(key), tostring(s.ext and s.ext.pt)))
        end
    end
end
