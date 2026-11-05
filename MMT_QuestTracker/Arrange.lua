-- MMT Quest Tracker: the order of zones and quests (Settings > Order).
--
--   currentZoneFirst  the zone you are in on top (quest-log header = zone name;
--                     in a dungeon its name, e.g. "The Deadmines")
--   otherZones        show | collapse | hide: the other zones, while the zone
--                     you are in has quests
--   zoneOrder         log (quest-log order) | near (your continent first, then
--                     the nearest zone) | name (A-Z)
--   questOrder        log | level | progress (furthest along for the team first)
--                     | near (Questie's distance to the nearest objective)
--   readyQuests       keep | top | bottom: quests ready to turn in
--   useQuestie        distances from Questie's database when Questie is loaded
--
-- Without Questie "near" uses the distance to the middle of each zone (from the
-- game's own maps), so it orders zones, not quests. Unknown zones (class or
-- profession headers) keep their log order after the known ones.
-- While a "near" order is on, a 5 s ticker re-sorts after you moved and
-- redraws only when the order changed.

local _, mod = ...
local MMT = MMT
local M = mod.M

local MOVED_YARDS = 20       -- re-sort after moving this far
local TICK = 5               -- seconds between position checks
local QUESTIE_FAR = 500000   -- Questie's distances on another continent / instance start here

---------------------------------------------------------------------------
-- Where you are
---------------------------------------------------------------------------
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end

-- names that count as "the zone you are in": the real zone text and the map
-- (and its parents down to zone level) you stand on
function mod.CurrentZoneNames()
    local names = {}
    local function Add(n) if type(n) == "string" and n ~= "" and not MMT.IsSecret(n) then names[n] = true end end
    Add(Call(GetRealZoneText))
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local map = Call(C_Map.GetBestMapForUnit, "player")
        local guard = 0
        while map and map > 0 and guard < 6 do
            guard = guard + 1
            local info = Call(C_Map.GetMapInfo, map)
            if not info or (info.mapType or 0) < 3 then break end   -- 3 = zone; below: continent, world
            Add(info.name)
            map = info.parentMapID
        end
    end
    return names
end

-- your position: continent ID, x, y (world yards) or nil
local function PlayerWorld()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return nil end
    local map = Call(C_Map.GetBestMapForUnit, "player")
    if not map then return nil end
    local pos = Call(C_Map.GetPlayerMapPosition, map, "player")
    if not pos then return nil end
    local cont, world = Call(C_Map.GetWorldPosFromMapPos, map, pos)
    if not (cont and world and world.x) then return nil end
    return { cont = cont, x = world.x, y = world.y }
end
mod.PlayerWorld = PlayerWorld

---------------------------------------------------------------------------
-- Zones of the world map: name -> uiMapID, middle of each zone
---------------------------------------------------------------------------
local zoneMaps
local function ZoneMaps()
    if zoneMaps then return zoneMaps end
    zoneMaps = {}
    if not (C_Map and C_Map.GetMapChildrenInfo) then return zoneMaps end
    for _, root in ipairs({ 946, 947 }) do   -- Cosmic (with Outland where there is one), Azeroth
        local list = Call(C_Map.GetMapChildrenInfo, root, nil, true)
        for _, info in ipairs(list or {}) do
            if info.mapType == 3 and info.name and not zoneMaps[info.name] then zoneMaps[info.name] = info.mapID end
        end
        if next(zoneMaps) then break end
    end
    return zoneMaps
end

local centres = {}
local function ZoneCentre(mapID)
    if centres[mapID] ~= nil then return centres[mapID] or nil end
    centres[mapID] = false
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local cont, world = Call(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0.5, 0.5))
        if cont and world and world.x then centres[mapID] = { cont = cont, x = world.x, y = world.y } end
    end
    return centres[mapID] or nil
end

local function Dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

---------------------------------------------------------------------------
-- Questie (optional): its distance to the nearest open objective (or the
-- turn-in NPC once done). Only for quests in your own log; nil when Questie
-- isn't loaded, doesn't know the quest, or the target is on another continent.
---------------------------------------------------------------------------
local qCache, qCacheTime = {}, 0

local function QuestieLoaded()
    local L = rawget(_G, "QuestieLoader")
    return type(L) == "table" and type(L.ImportModule) == "function" and L or nil
end

function mod.QuestieAvailable()
    return QuestieLoaded() ~= nil
end

local function QuestieDistance(id)
    if not M.db.useQuestie then return nil end
    local L = QuestieLoaded()
    if not L then return nil end
    local now = GetTime()
    if now - qCacheTime > 1 then wipe(qCache) qCacheTime = now end
    local c = qCache[id]
    if c ~= nil then return c or nil end
    local ok, d = pcall(function()
        local player = L:ImportModule("QuestiePlayer")
        if not (player and player.currentQuestlog and player.currentQuestlog[id]) then return nil end
        local db, du = L:ImportModule("QuestieDB"), L:ImportModule("DistanceUtils")
        if type(db.GetQuest) ~= "function" or type(du.GetNearestSpawnForQuest) ~= "function" then return nil end
        local q = db.GetQuest(id)
        if type(q) ~= "table" or type(q.Objectives) ~= "table" or type(q.IsComplete) ~= "function" then return nil end
        local _, _, _, dist = du.GetNearestSpawnForQuest(q)
        return dist
    end)
    if ok and type(d) == "number" and d < QUESTIE_FAR then
        qCache[id] = d
        return d
    end
    if not ok then M:Debug("Questie distance for %s: %s", tostring(id), tostring(d)) end
    qCache[id] = false
    return nil
end

---------------------------------------------------------------------------
-- Team progress of a quest: average over the shown members that have it
---------------------------------------------------------------------------
local function Fraction(mq)
    if mq.state == 1 then return 1 end
    if mq.state == -1 then return 0 end
    local n = #mq.obj
    if n == 0 then return 0 end
    local s = 0
    for _, o in ipairs(mq.obj) do
        if o.done then s = s + 1
        elseif (o.need or 0) > 0 then s = s + math.min(1, math.max(0, (o.have or 0) / o.need)) end
    end
    return s / n
end

local function TeamProgress(data, members, id)
    local sum, n = 0, 0
    for _, key in ipairs(members) do
        local mq = data[key] and data[key].quests[id]
        if mq then sum, n = sum + Fraction(mq), n + 1 end
    end
    return n > 0 and sum / n or 0
end

---------------------------------------------------------------------------
-- Arrange
---------------------------------------------------------------------------
function mod.NeedsPosition()
    local cfg = M.db
    return cfg.zoneOrder == "near" or cfg.questOrder == "near"
end

-- zones: zone names in first-seen order; byZone: name -> quest IDs (own in log
-- order, then teammates'); ctx = { data, members, own, ready = fn(id) -> bool }.
-- Sorts each byZone list in place and returns the ordered zone list and the set
-- of zones you are in that have quests (nil when none).
function mod.Arrange(zones, byZone, ctx)
    local cfg = M.db

    -- quests inside each zone
    local qd = {}   -- id -> Questie distance (own quests, "near" only)
    for _, zone in ipairs(zones) do
        local list = byZone[zone]
        local index, key = {}, {}
        for i, id in ipairs(list) do
            index[id] = i
            -- Questie distances: for "near" quests, and for "near" zones whatever the quest order
            if (cfg.questOrder == "near" or cfg.zoneOrder == "near") and ctx.own[id] then qd[id] = QuestieDistance(id) end
            if cfg.questOrder == "level" then
                key[id] = ctx.level(id) or 0
            elseif cfg.questOrder == "progress" then
                key[id] = -TeamProgress(ctx.data, ctx.members, id)   -- furthest along first
            elseif cfg.questOrder == "near" then
                key[id] = qd[id]
            end
        end
        local readyRank = {}
        if cfg.readyQuests == "top" or cfg.readyQuests == "bottom" then
            local top = cfg.readyQuests == "top"
            for _, id in ipairs(list) do
                local r = ctx.ready(id)
                readyRank[id] = (r == top) and 0 or 1
            end
        end
        table.sort(list, function(a, b)
            local ra, rb = readyRank[a] or 0, readyRank[b] or 0
            if ra ~= rb then return ra < rb end
            local ka, kb = key[a], key[b]
            if ka ~= kb then
                if ka == nil then return false end   -- no distance: after the ones with one
                if kb == nil then return true end
                return ka < kb
            end
            return index[a] < index[b]
        end)
    end

    -- the zones you are in (with quests)
    local here = mod.CurrentZoneNames()
    local current
    for _, zone in ipairs(zones) do
        if here[zone] then current = current or {}; current[zone] = true end
    end

    -- zone order
    local zindex, zrank, zdist = {}, {}, {}
    local player = cfg.zoneOrder == "near" and PlayerWorld() or nil
    local maps = cfg.zoneOrder == "near" and ZoneMaps() or nil
    for i, zone in ipairs(zones) do
        zindex[zone] = i
        zrank[zone] = 0
        if cfg.zoneOrder == "near" then
            -- Questie: the nearest quest of the zone; otherwise the middle of the zone
            local best
            for _, id in ipairs(byZone[zone]) do
                local d = qd[id]
                if d and (not best or d < best) then best = d end
            end
            local mapID = maps[zone]
            local c = mapID and ZoneCentre(mapID)
            if best then
                zrank[zone], zdist[zone] = 0, best
            elseif c and player and c.cont == player.cont then
                zrank[zone], zdist[zone] = 0, Dist(c.x, c.y, player.x, player.y)
            elseif c then
                zrank[zone] = 1   -- another continent
            else
                zrank[zone] = 2   -- not a zone of the map (class quests, dungeons, ...)
            end
        end
        if cfg.currentZoneFirst and current and current[zone] then zrank[zone] = -1 end
    end
    local ordered = {}
    for i, zone in ipairs(zones) do ordered[i] = zone end
    table.sort(ordered, function(a, b)
        if zrank[a] ~= zrank[b] then return zrank[a] < zrank[b] end
        local da, db = zdist[a], zdist[b]
        if da ~= db then
            if da == nil then return false end
            if db == nil then return true end
            return da < db
        end
        if cfg.zoneOrder == "name" and a ~= b then return a < b end
        return zindex[a] < zindex[b]
    end)
    return ordered, current
end

---------------------------------------------------------------------------
-- Zones collapsed / opened automatically ("otherZones" = collapse). The
-- user's own +/- on a zone wins until the next zone change.
---------------------------------------------------------------------------
mod.autoOpened = {}

function mod.ResetAutoOpened()
    wipe(mod.autoOpened)
end

---------------------------------------------------------------------------
-- Re-sorting
---------------------------------------------------------------------------
local function ZoneChanged()
    mod.ResetAutoOpened()
    if mod.Redraw then mod.Redraw() end
end
M:On("ZONE_CHANGED_NEW_AREA", ZoneChanged)
M:On("PLAYER_ENTERING_WORLD", ZoneChanged)

local last
local function Tick()
    if not (M.enabled and M.db.show and mod.NeedsPosition() and mod.BuildEntries) then return end
    local p = PlayerWorld()
    if not p then return end
    if last and last.cont == p.cont and Dist(last.x, last.y, p.x, p.y) < MOVED_YARDS then return end
    last = p
    mod.BuildEntries()   -- sets mod.orderSig
    if mod.orderSig ~= mod.drawnSig then mod.Redraw() end
end

MMT.OnLogin(function()
    C_Timer.NewTicker(TICK, function()
        local ok, err = pcall(Tick)
        if not ok then M:Debug("arrange tick: %s", tostring(err)) end
    end)
end)

function mod.ArrangeReport()
    local cfg = M.db
    local here = {}
    for n in pairs(mod.CurrentZoneNames()) do here[#here + 1] = n end
    local p = PlayerWorld()
    return ("order: currentZoneFirst=%s otherZones=%s zoneOrder=%s questOrder=%s readyQuests=%s useQuestie=%s (Questie %s)  here=%s  pos=%s  zone maps=%d"):format(
        tostring(cfg.currentZoneFirst), tostring(cfg.otherZones), tostring(cfg.zoneOrder), tostring(cfg.questOrder),
        tostring(cfg.readyQuests), tostring(cfg.useQuestie), mod.QuestieAvailable() and "loaded" or "not loaded",
        table.concat(here, "/"), p and ("%d:%.0f,%.0f"):format(p.cont, p.x, p.y) or "none", (function()
            local n = 0 for _ in pairs(ZoneMaps()) do n = n + 1 end return n end)())
end
