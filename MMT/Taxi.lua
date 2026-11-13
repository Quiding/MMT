-- MMT: take flight paths with the team (as in EMA).
--
-- When a character picks a destination at a flight master, its client tells
-- the team (TAXI:<destination name>, leader first). Every team member whose
-- flight map is open at that moment (talking to a flight master) takes the
-- same destination. A member who opens the flight map within a few seconds
-- after the message still follows (broadcast "interact" arrives a bit later
-- on some clients). Destinations are matched by name.
--
-- Team members wait "delay" seconds (1-5) before taking the flight, so their
-- flight maps have time to open. With "Flight-Train" they go one by one, in
-- team order after the one who picked it: the first after the delay, the next
-- after twice the delay, and so on.
-- Every member answers the one who picked the flight (NOTE:TAXI): ok, or why
-- not: k = flight path not known, u = can't be reached, m = not at a flight
-- master, c = in combat, t = already on a flight, e = the game refused.

local _, ns = ...

local GRACE = 5            -- seconds a request waits (after its delay) for this client's flight map to open
local mapOpen = false
local followingTaxi = false   -- MMT itself takes the flight: don't announce it again
local pending                 -- { name, from, ready }: a flight to follow (ready: its delay is over)

local function Cfg() return ns.db and ns.db.taxi end

---------------------------------------------------------------------------
-- Flight map nodes
---------------------------------------------------------------------------
-- index of the destination with that name on the open flight map, and whether it can be flown to
local function FindNode(name)
    if NumTaxiNodes and TaxiNodeName then
        for i = 1, (NumTaxiNodes() or 0) do
            if TaxiNodeName(i) == name then
                local kind = TaxiNodeGetType and TaxiNodeGetType(i)
                return i, kind == nil or kind == "REACHABLE"
            end
        end
    end
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
        local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, GetTaxiMapID())
        for _, node in ipairs(ok and nodes or {}) do
            if node.name == name then
                local reachable = not (Enum and Enum.FlightPathState) or node.state == Enum.FlightPathState.Reachable
                return node.slotIndex, reachable
            end
        end
    end
end

local function NodeName(index)
    if TaxiNodeName then
        local ok, name = pcall(TaxiNodeName, index)
        if ok and type(name) == "string" and not ns.IsSecret(name) and name ~= "" then return name end
    end
end

---------------------------------------------------------------------------
-- Following a team member's flight
---------------------------------------------------------------------------
-- the leader's chat: who followed, who couldn't (k = not known, u = can't be reached)
local WHY = {
    k = "that flight path isn't known there", u = "it can't be reached from there",
    m = "not at a flight master", c = "in combat", t = "already on a flight", e = "the game refused it",
}

-- answer the one who picked the flight (its client prints it)
local function Tell(ok, name, why, toKey)
    local cfg = Cfg()
    if not (cfg and cfg.tellLeader) then return end
    local msg = ok and ("NOTE:TAXI:1:" .. name) or ("NOTE:TAXI:0:" .. why .. ":" .. name)
    if toKey and not ns.IsSelf(toKey) and ns.SendAddon and ns.WhisperTarget then
        ns.SendAddon(msg, "WHISPER", ns.WhisperTarget(toKey), "NORMAL")
    elseif ns.TellLeader then
        ns.TellLeader(msg)
    end
    ns.Debug("taxi: answer %s %s (%s)", ok and "ok" or ("no: " .. tostring(WHY[why] or why)), name, ns.Repr(toKey))
end

local function Take(name, fromKey)
    local who = fromKey and ns.ShownName(fromKey) or "a team member"
    if ns.Safe(UnitOnTaxi, "player") then Tell(false, name, "t", fromKey) return end
    if InCombatLockdown() or ns.Safe(UnitAffectingCombat, "player") then
        ns.Print("%s flies to %s, but you are in combat.", who, name)
        Tell(false, name, "c", fromKey)
        return
    end
    local index, reachable = FindNode(name)
    if not index then
        ns.Print("%s flies to %s, but that flight path isn't known on this character.", who, name)
        Tell(false, name, "k", fromKey)
        return
    end
    if not reachable then
        ns.Print("%s flies to %s, but it can't be reached from here.", who, name)
        Tell(false, name, "u", fromKey)
        return
    end
    followingTaxi = true
    local ok, err = pcall(TakeTaxiNode, index)
    followingTaxi = false
    ns.Debug("taxi: follow %s to %s (node %s) -> %s %s", ns.Repr(fromKey), name, tostring(index), tostring(ok), tostring(err or ""))
    if ok and Cfg().report then ns.Print("Flying to %s with %s.", name, who) end
    if ok then Tell(true, name, nil, fromKey) else Tell(false, name, "e", fromKey) end
end

-- the leader's client: notes from the team, collected for 3 seconds:
--   Taxi: John and Monika fly to Ironforge too.
--   Taxi: Apple can't fly to Ironforge: that flight path isn't known there.
local taxiNotes = ns.ChatBatch(3, function(list)
    local groups, at = {}, {}
    for _, e in ipairs(list) do
        local id = e.why .. "\1" .. e.name
        local g = at[id]
        if not g then g = { why = e.why, name = e.name, who = {} } groups[#groups + 1] = g at[id] = g end
        g.who[#g.who + 1] = e.who
    end
    for _, g in ipairs(groups) do
        if g.why == "ok" then
            ns.Print("Taxi: %s %s to %s too.", ns.AndList(g.who), #g.who == 1 and "flies" or "fly", g.name)
        else
            ns.Print("|cffff6666Taxi: %s can't fly to %s: %s.|r", ns.AndList(g.who), g.name, WHY[g.why] or WHY.k)
        end
    end
end)
ns.Listen("TEAM_MESSAGE", function(key, sender, text, _, channel)
    local okFlag, rest = text:match("^NOTE:TAXI:([01]):(.+)$")
    if not okFlag or not ns.AcceptNotice(channel) then return end
    local who = ns.ShownName(key)
    if okFlag == "1" then
        taxiNotes.Add({ why = "ok", name = rest, who = who })
    else
        local why, name = rest:match("^(%a):(.+)$")
        taxiNotes.Add({ why = WHY[why] and why or "k", name = name or rest, who = who })
    end
end)

-- seconds this client waits before taking a flight `fromKey` picked
local function Wait(fromKey)
    local cfg = Cfg()
    local delay = math.max(1, math.min(5, tonumber(cfg.delay) or 1))
    if not cfg.train then return delay end
    -- Flight-Train: place in team order after the one who picked it (wrapping around)
    local order = ns.SortedMembers()
    local start
    for i, k in ipairs(order) do if ns.NormKey(k) == ns.NormKey(fromKey) then start = i break end end
    if not start then return delay end
    local place = 0
    for n = 1, #order - 1 do
        local k = order[(start - 1 + n) % #order + 1]
        if ns.IsSelf(k) then return delay * (place + 1) end
        if ns.IsSelf(k) or (ns.UnitForMember and ns.UnitForMember(k)) then place = place + 1 end
    end
    return delay
end

local function Due(p)
    if pending ~= p then return end
    if mapOpen then
        pending = nil
        Take(p.name, p.from)
    else
        -- not at a flight master (yet): wait for the map a little longer
        p.ready = true
        ns.Debug("taxi: %s flies to %s; flight map not open here (waiting %d s)", ns.Repr(p.from), p.name, GRACE)
        C_Timer.After(GRACE, function()
            if pending == p then
                pending = nil
                ns.Print("%s flies to %s, but you aren't at a flight master.", ns.ShownName(p.from), p.name)
                Tell(false, p.name, "m", p.from)
            end
        end)
    end
end

ns.Listen("TEAM_MESSAGE", function(key, sender, text)
    local name = text:match("^TAXI:(.+)$")
    if not name then return end
    local cfg = Cfg()
    if not (cfg and cfg.enabled) then return end
    local wait = Wait(key)
    local p = { name = name, from = key }
    pending = p
    ns.Debug("taxi: %s took the flight to %s; following in %.1f s%s", ns.Repr(key), name, wait, cfg.train and " (Flight-Train)" or "")
    C_Timer.After(wait, function() Due(p) end)
end)

ns.On("TAXIMAP_OPENED", function()
    mapOpen = true
    local p = pending
    local cfg = Cfg()
    -- only once the delay is over (else Due takes it when it is)
    if p and p.ready and cfg and cfg.enabled then
        pending = nil
        -- the map needs a moment to fill
        C_Timer.After(0.2, function() if mapOpen then Take(p.name, p.from) end end)
    end
end)
ns.On("TAXIMAP_CLOSED", function() mapOpen = false end)

---------------------------------------------------------------------------
-- Announcing the own choice
---------------------------------------------------------------------------
if hooksecurefunc and TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(index)
        local cfg = Cfg()
        if followingTaxi or not (cfg and cfg.enabled) then return end
        local name = NodeName(index)
        if not name then return end
        ns.Debug("taxi: taking %s, telling the team", name)
        if cfg.report then
            local delay = math.max(1, math.min(5, tonumber(cfg.delay) or 1))
            ns.Print("Taxi: you fly to %s; the team follows %s.", name,
                cfg.train and ("one by one, every " .. delay .. " s") or ("in " .. delay .. " s"))
        end
        if ns.SendAlert then ns.SendAlert("TAXI:" .. name) end
    end)
end
