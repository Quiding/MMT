-- MMT: flights in the Info window. Every client notices when its character is
-- on a flight path (UnitOnTaxi) and sends it with the heartbeat:
--   "fl=<destination>~<arrival in server time, 0 = not known>"
-- right away at take-off and landing. The row then shows "Fly to X, mm:ss" in
-- place of the XP, and "arrived X" for 5 seconds after landing. Together with
-- "LvlUp available" the two take turns every 5 seconds.
--
-- Flight times are learned: the game doesn't tell addons how long a flight
-- takes, so each landing stores the time of the route (from -> to) in MMTDB
-- (this account, all characters). Each landing checks the stored time again: a
-- difference of up to 2 seconds is averaged (lag), a bigger one replaces it.
-- Routes not flown yet use the times that come with MMT (FlightTimes.lua); the
-- rest show no time on their first flight. "/mmt flights" exports them all.

local _, ns = ...

local ARRIVED_SHOW = 5
local TAKE_GRACE = 60   -- a TakeTaxiNode up to this long before take-off names the route

local function Plain(v) if v == nil or ns.IsSecret(v) then return nil end return v end
local function Times()
    MMTDB.flightTimes = MMTDB.flightTimes or {}
    return MMTDB.flightTimes
end
local function Clean(name)   -- "Ironforge, Dun Morogh" -> "Ironforge"; nothing the heartbeat can't carry
    if type(name) ~= "string" then return nil end
    name = name:match("^([^,]+)") or name
    name = name:gsub("[:=~|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or nil
end
local function Route(from, to) return (from or "?") .. ">" .. (to or "?") end

-- seconds of a route: this account's own time, else the one that comes with MMT
function ns.FlightTime(from, to)
    local key = Route(from, to)
    return Times()[key] or (ns.DEFAULT_FLIGHT_TIMES or {})[key]
end

---------------------------------------------------------------------------
-- This character
---------------------------------------------------------------------------
local take       -- { from, to, at }: the last destination picked at a flight master
local flight     -- { from, to, start, expect }: on a flight now
local arrivedOwn -- { to, untl }

local function NodeName(index)
    if not TaxiNodeName then return nil end
    local ok, name = pcall(TaxiNodeName, index)
    return ok and Plain(name) or nil
end
local function CurrentNode()
    if NumTaxiNodes and TaxiNodeGetType then
        for i = 1, (tonumber(Plain(ns.Safe(NumTaxiNodes))) or 0) do
            local ok, kind = pcall(TaxiNodeGetType, i)
            if ok and kind == "CURRENT" then return NodeName(i) end
        end
    end
    return nil
end

if hooksecurefunc and TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(index)
        take = { from = Clean(CurrentNode()), to = Clean(NodeName(index)), at = GetTime() }
        ns.Debug("flight: picked %s -> %s", tostring(take.from), tostring(take.to))
    end)
end

local function OnTaxi() return Plain(ns.Safe(UnitOnTaxi, "player")) and true or false end

local function ArriveServerTime()
    if not (flight and flight.expect) then return 0 end
    local left = flight.expect - (GetTime() - flight.start)
    return math.floor(GetServerTime() + math.max(0, left) + 0.5)
end

ns.CoreHeartbeat("fl", function()
    if not flight then return nil end
    return (flight.to or "?") .. "~" .. ArriveServerTime()
end)

local function Push() if ns.ready and ns.BroadcastXP then ns.BroadcastXP(true) end end

local function TakeOff()
    local t = (take and GetTime() - take.at < TAKE_GRACE) and take or {}
    take = nil
    flight = { from = t.from, to = t.to, start = GetTime() }
    if t.from and t.to then flight.expect = ns.FlightTime(t.from, t.to) end
    ns.Debug("flight: took off %s -> %s, known time %s", tostring(flight.from), tostring(flight.to), tostring(flight.expect))
    Push()
end

local function Land()
    local f = flight
    flight = nil
    if f.from and f.to then
        local took = GetTime() - f.start
        if took > 5 then
            local key = Route(f.from, f.to)
            local old = Times()[key] or (ns.DEFAULT_FLIGHT_TIMES or {})[key]
            -- checked on every landing: up to 2 s off is lag (averaged), more replaces it
            local new
            if old and math.abs(took - old) <= 2 then new = (old + took) / 2 else new = took end
            Times()[key] = math.floor(new + 0.5)
            ns.Debug("flight: %s took %d s (known %s s, stored %d s)", key, took, tostring(old), Times()[key])
        end
    end
    arrivedOwn = { to = f.to or "?", untl = GetTime() + ARRIVED_SHOW }
    Push()
end

---------------------------------------------------------------------------
-- Team members: flying from the heartbeat, arrival when "fl" goes away
---------------------------------------------------------------------------
local wasFlying, arrived = {}, {}   -- [key] = destination; [key] = { to, untl }

local function TeamFlight(key, s)
    s = s or ns.status[key]
    local v = s and s.ext and s.ext.fl
    if type(v) ~= "string" then return nil end
    local to, at = v:match("^(.-)~(%d+)$")
    if not to then return nil end
    return to, tonumber(at)
end

ns.Listen("STATUS_CHANGED", function()
    for _, key in ipairs(ns.SortedMembers()) do
        if not ns.IsSelf(key) then
            local to = TeamFlight(key)
            if to then
                wasFlying[key] = to
            elseif wasFlying[key] then
                arrived[key] = { to = wasFlying[key], untl = GetTime() + ARRIVED_SHOW }
                wasFlying[key] = nil
            end
        end
    end
end)

-- flying: destination and seconds left (nil when not known); else nil
function ns.FlightOf(key, s)
    if ns.IsSelf(key) then
        if not flight then return nil end
        local left = flight.expect and math.max(0, flight.expect - (GetTime() - flight.start)) or nil
        return flight.to or "?", left
    end
    local to, at = TeamFlight(key, s)
    if not to then return nil end
    local left = (at and at > 0) and math.max(0, at - GetServerTime()) or nil
    return to, left
end

local function ArrivedAt(key)
    local a = ns.IsSelf(key) and arrivedOwn or arrived[key]
    if a and GetTime() < a.untl then return a.to end
    return nil
end

---------------------------------------------------------------------------
-- The notice in place of the XP (XPPieces.lua: value / rested pieces)
---------------------------------------------------------------------------
local function Hex(r, g, b) return ns.XPHex(r, g, b) end
local LEVEL_UP = function() return Hex(0.3, 1, 0.3) .. "LvlUp available|r" end

local function Clock(sec)
    sec = math.floor(sec + 0.5)
    return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

-- text, pulse: what the row shows instead of its XP, or nil
function ns.RowNotice(key, s)
    local flightsOn = ns.db.xp.flightHint ~= false
    if flightsOn then
        local to = ArrivedAt(key)
        if to then return Hex(0.3, 1, 0.3) .. (to == "?" and "arrived" or ("arrived " .. to)) .. "|r", true end
    end
    local fly
    if flightsOn then
        local to, left = ns.FlightOf(key, s)
        if to then
            fly = Hex(0.55, 0.85, 1) .. (to == "?" and "Flying" or ("Fly to " .. to)) .. (left and (", " .. Clock(left)) or "") .. "|r"
        end
    end
    local lvl = ns.db.xp.levelUpHint ~= false and ns.db.xp.barMode ~= "REP" and ns.CanLevelUp and ns.CanLevelUp(key, s)
    local phase = math.floor(GetTime() / 5) % 2 == 0
    if fly and lvl then
        if phase then return fly end
        return LEVEL_UP(), true
    end
    if fly then return fly end
    if lvl and phase then return LEVEL_UP(), true end
    return nil
end

-- the row tooltip (XPWindow.lua)
function ns.FlightTooltip(tip, key, s)
    local to, left = ns.FlightOf(key, s)
    if not to then return end
    tip:AddDoubleLine("Flying to", to .. (left and ("  (" .. Clock(left) .. ")") or "  (time not known yet)"),
        1, 1, 1, 0.55, 0.85, 1)
end

---------------------------------------------------------------------------
-- Once a second: take-off / landing, and the countdown in the window
---------------------------------------------------------------------------
ns.OnLogin(function()
    if OnTaxi() then flight = { start = GetTime() } end   -- logged in / reloaded on a flight
    C_Timer.NewTicker(1, function()
        local on = OnTaxi()
        if on and not flight then TakeOff()
        elseif not on and flight then Land() end
        -- redraw while somebody flies or just arrived (mm:ss counts down)
        if not ns.UpdateXPWindow or ns.db.xp.flightHint == false then return end
        local busy = flight or (arrivedOwn and GetTime() < arrivedOwn.untl + 1)
        if not busy then
            for key in pairs(wasFlying) do busy = true break end
        end
        if not busy then
            for _, a in pairs(arrived) do if GetTime() < a.untl + 1 then busy = true break end end
        end
        if busy then ns.UpdateXPWindow() end
    end)
end)

-- "/mmt flights": every known route as Lua lines for FlightTimes.lua
function ns.ExportFlightTimes()
    local all = {}
    for k, v in pairs(ns.DEFAULT_FLIGHT_TIMES or {}) do all[k] = v end
    local own = 0
    for k, v in pairs(Times()) do all[k] = v own = own + 1 end
    local keys = {}
    for k in pairs(all) do if not k:find("?", 1, true) then keys[#keys + 1] = k end end
    table.sort(keys)
    local lines = { ("-- MMT flight times: %d routes (%d flown on this account), faction %s"):format(
        #keys, own, tostring(UnitFactionGroup and UnitFactionGroup("player"))) }
    for _, k in ipairs(keys) do
        lines[#lines + 1] = ("    [%q] = %d,"):format(k, all[k])
    end
    ns.ShowText("MMT flight times", table.concat(lines, "\n"))
end

-- /mmt debug dump
function ns.FlightReport(add)
    local n = 0
    for _ in pairs(Times()) do n = n + 1 end
    add(("-- Flight  on taxi=%s  flight=%s  routes learned=%d  hint=%s"):format(tostring(OnTaxi()),
        flight and (Route(flight.from, flight.to) .. " expect=" .. tostring(flight.expect)) or "none", n,
        tostring(ns.db.xp.flightHint ~= false)))
    for _, key in ipairs(ns.SortedMembers()) do
        local s = ns.status[key]
        if not ns.IsSelf(key) and s and s.ext and s.ext.fl then add(("  %s fl=%s"):format(ns.Repr(key), s.ext.fl)) end
    end
end
