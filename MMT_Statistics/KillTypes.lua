-- MMT Statistics: what kind of NPC a kill was, nameplate kills, dungeon
-- encounters and deaths by falling.
--
-- NPC kinds, remembered by name for the whole account (Store().npcs[name]):
--   { c = classification ("normal" | "elite" | "rare" | "rareelite" |
--         "worldboss" | "trivial" | "minus"),
--     b = true  a "big baddie": the game's boss flag (UnitIsBossMob), a world
--               boss or a skull level (??),
--     d = true  a dungeon boss: a boss of a dungeon encounter (a boss unit, or
--               the encounter's name); raid encounter bosses are big
--               baddies instead (rb = true),
--     cr = true a critter,
--     z = zone key of the instance it was seen in (dungeon bosses) }
-- Read whenever an NPC is targeted, moused over, gets a nameplate or is a boss
-- unit, so kills counted from the experience line or a team message know
-- their kind too (an NPC never seen up close stays "normal").
--
-- More kills: an NPC with a nameplate that dies while this character or its
-- group has it tapped (no XP needed: level 60, grey NPCs, AoE, pets). Counted
-- only when it was seen alive, so a corpse coming into view doesn't count.
-- Dungeon encounters (ENCOUNTER_END) count their boss when nothing else did.
-- Deaths: every death (c.deathAll), and the ones right after falling
-- (c.gravity).

local _, mod = ...
local MMT = MMT
local M = mod.M

local Safe, IsSecret = MMT.Safe, MMT.IsSecret
local function Plain(v) if v == nil or IsSecret(v) then return nil end return v end

local CRITTER = { Critter = true, Kleintier = true, Bestiole = true, ["Alimaña"] = true, Animale = true,
    ["Животное"] = true, ["Bicho"] = true, ["동물"] = true, ["小动物"] = true, ["小動物"] = true }

local function Npcs()
    local s = mod.Store()
    s.npcs = s.npcs or {}
    return s.npcs
end
mod.Npcs = Npcs

local encounterUnits = {}   -- names of the current encounter's boss units

-- remembers what kind of NPC the unit is
local function InRaid()
    local inInstance, kind = Safe(IsInInstance)
    return inInstance and kind == "raid"
end

-- text for the debug log: "rare, big baddie (raid boss)"
local function KindText(n)
    local t = {}
    if n.c == "rare" or n.c == "rareelite" then t[#t + 1] = "rare" end
    if n.d then t[#t + 1] = "dungeon boss" end
    if n.b then t[#t + 1] = n.rb and "big baddie (raid boss)" or "big baddie" end
    if n.cr then t[#t + 1] = "critter" end
    return #t > 0 and table.concat(t, ", ") or ("normal" .. (n.c and (" (" .. n.c .. ")") or ""))
end
mod.NpcKindText = function(name) local n = Npcs()[name] return n and KindText(n) or "unknown" end

-- marks a boss of an encounter: a dungeon boss, or in a raid a big baddie
local function MarkBoss(n, zk)
    n.z = zk
    if InRaid() then n.b, n.rb, n.d = true, true, nil else n.d = true end
end

local function Learn(unit)
    if not Safe(UnitExists, unit) or Safe(UnitIsPlayer, unit) then return end
    local name = Plain(Safe(UnitName, unit))
    if type(name) ~= "string" or name == "" then return end
    local n = Npcs()[name] or {}
    local before = Npcs()[name] and KindText(n) or nil
    local cls = Plain(Safe(UnitClassification, unit))
    if type(cls) == "string" then n.c = cls end
    local level = tonumber(Plain(Safe(UnitLevel, unit)))
    if Safe(UnitIsBossMob, unit) or cls == "worldboss" or level == -1 then n.b = true end
    local ctype = Plain(Safe(UnitCreatureType, unit))
    if type(ctype) == "string" and CRITTER[ctype] then n.cr = true end
    local zk, _, inst = mod.CurrentZone()   -- (Leveling.lua; not "x and f()": that keeps one value)
    if inst and (encounterUnits[name] or unit:match("^boss%d")) then MarkBoss(n, zk) end
    Npcs()[name] = n
    local now = KindText(n)
    if now ~= before and not now:match("^normal") then   -- special kinds only (no log spam)
        M:Debug("npc %s: %s (%s, level %s)", name, now, unit, tostring(level))
    end
end
mod.LearnUnit = Learn

-- "rare" | "dboss" | "big" | "critter" | nil for a name
function mod.NpcKinds(name)
    local n = Npcs()[name]
    if not n then return {} end
    return { rare = n.c == "rare" or n.c == "rareelite" or nil, dboss = n.d or nil, big = n.b or nil, critter = n.cr or nil }
end

M:On("PLAYER_TARGET_CHANGED", function() Learn("target") end)
M:On("UPDATE_MOUSEOVER_UNIT", function() Learn("mouseover") end)
M:On("PLAYER_SOFT_ENEMY_CHANGED", function() Learn("softenemy") end)
M:On("INSTANCE_ENCOUNTER_ENGAGE_UNIT", function()
    for i = 1, 5 do
        local unit = "boss" .. i
        local name = Plain(Safe(UnitName, unit))
        if type(name) == "string" then encounterUnits[name] = true end
        Learn(unit)
    end
end)

---------------------------------------------------------------------------
-- Nameplate kills
---------------------------------------------------------------------------
local alive = {}   -- [nameplate unit] = name, while alive
local function PlateCheck(unit)
    if type(unit) ~= "string" or not unit:match("^nameplate%d") then return end
    if Safe(UnitIsDead, unit) then
        local name = alive[unit]
        alive[unit] = nil
        if name and not Safe(UnitIsTapDenied, unit) and M.db.trackKills and mod.CountKill then
            mod.CountKill(name, "nameplate")
        end
        return
    end
    if Safe(UnitIsPlayer, unit) or not Safe(UnitCanAttack, "player", unit) then alive[unit] = nil return end
    local name = Plain(Safe(UnitName, unit))
    if type(name) == "string" and name ~= "" then alive[unit] = name end
end
M:On("NAME_PLATE_UNIT_ADDED", function(unit) alive[unit] = nil Learn(unit) PlateCheck(unit) end)
M:On("NAME_PLATE_UNIT_REMOVED", function(unit) PlateCheck(unit) alive[unit] = nil end)
M:On("UNIT_HEALTH", function(unit) if type(unit) == "string" and unit:match("^nameplate%d") then PlateCheck(unit) end end)

---------------------------------------------------------------------------
-- Dungeon encounters
---------------------------------------------------------------------------
local lastEncounter   -- debug report
M:On("ENCOUNTER_START", function(_, name)
    for k in pairs(encounterUnits) do encounterUnits[k] = nil end
    M:Debug("encounter started: %s (%s)", tostring(Plain(name)), InRaid() and "raid" or "dungeon")
    lastEncounter = ("%s, started %s"):format(tostring(Plain(name)), date("%H:%M"))
end)
M:On("ENCOUNTER_END", function(_, name, _, _, success)
    if success ~= 1 and success ~= true then
        M:Debug("encounter ended without a win: %s", tostring(Plain(name)))
    end
end)
M:On("ENCOUNTER_END", function(_, name, _, _, success)
    name = Plain(name)
    if success ~= 1 and success ~= true then return end
    if type(name) ~= "string" or name == "" then return end
    local zk, _, inst = mod.CurrentZone()   -- (Leveling.lua; not "x and f()": that keeps one value)
    if not inst then return end
    -- dungeon bosses; raid bosses are big baddies
    local n = Npcs()[name] or {}
    MarkBoss(n, zk)
    Npcs()[name] = n
    for unitName in pairs(encounterUnits) do
        local u = Npcs()[unitName] or {}
        MarkBoss(u, zk)
        Npcs()[unitName] = u
    end
    -- the bosses (a kill already counted in the last seconds isn't counted again);
    -- without boss units the encounter's name
    local names = {}
    for unitName in pairs(encounterUnits) do names[#names + 1] = unitName end
    if #names == 0 then names[1] = name end
    for k in pairs(encounterUnits) do encounterUnits[k] = nil end
    if mod.CountKill then
        for _, n2 in ipairs(names) do mod.CountKill(n2, "encounter") end
    end
    M:Debug("encounter won: %s (%s) -> %s", name, InRaid() and "raid: big baddies" or "dungeon bosses",
        table.concat(names, ", "))
    lastEncounter = ("%s, won %s"):format(name, date("%H:%M"))
end)

---------------------------------------------------------------------------
-- Deaths: all of them, and by falling
---------------------------------------------------------------------------
local lastFalling = 0
local fallWatch = CreateFrame("Frame")
local acc = 0
fallWatch:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.2 then return end
    acc = 0
    if Safe(IsFalling) then lastFalling = GetTime() end
end)

M:On("PLAYER_DEAD", function()
    if not M.db.trackKills then return end
    local c = mod.Char()
    if not c then return end
    c.deathAll = (c.deathAll or 0) + 1
    if GetTime() - lastFalling < 2 then
        c.gravity = (c.gravity or 0) + 1
        M:Debug("death by gravity")
    end
    if mod.Redraw then mod.Redraw() end
end)

---------------------------------------------------------------------------
-- Views for the Kills tab (characters of a scope: Module.lua mod.InScope)
---------------------------------------------------------------------------
local function ScopeChars(scope)
    local list = {}
    for key, c in pairs(mod.Store().chars) do
        if mod.InScope(scope, key) then list[#list + 1] = c end
    end
    return list
end

local function IsKind(name, kind)
    if kind == "ALL" or not kind then return true end
    return mod.NpcKinds(name)[kind] == true
end

-- zone choice value of a zone key: land zones by name (a zone read once
-- without its map ID is the same), instances by key
local function ZoneValue(c, zk)
    local z = c.zones and c.zones[zk]
    if zk:sub(1, 2) == "i:" then return zk, z and z.n or zk end
    local name = z and z.n or zk:gsub("^%a:", "")
    return "name:" .. name, name
end

-- { all, rare, dboss, big, critter, deaths, gravity }
function mod.KillTotals(scope)
    local t = { all = 0, rare = 0, dboss = 0, big = 0, critter = 0, deaths = 0, gravity = 0 }
    for _, c in ipairs(ScopeChars(scope)) do
        t.all = t.all + (c.killTotal or 0)
        for name, n in pairs(c.kills or {}) do
            local kinds = mod.NpcKinds(name)
            for _, kind in ipairs({ "rare", "dboss", "big", "critter" }) do
                if kinds[kind] then t[kind] = t[kind] + n end
            end
        end
        t.deaths = t.deaths + math.max(c.deathAll or 0, c.deathTotal or 0)
        t.gravity = t.gravity + (c.gravity or 0)
    end
    return t
end

-- top n of field "killDetail" (kills) or "deathDetail" (killed by) for a kind
-- and a zone ("ALL", "name:<zone>", "i:<map>"): { {name, count}, ... }
function mod.TopKills(scope, kind, zone, field, n)
    local sum = {}
    for _, c in ipairs(ScopeChars(scope)) do
        if zone == "ALL" then
            -- all of history (kills before 1.0.18 have no zone)
            for name, count in pairs(c[field == "killDetail" and "kills" or "deaths"] or {}) do
                if IsKind(name, kind) then sum[name] = (sum[name] or 0) + count end
            end
        else
            for name, map in pairs(c[field] or {}) do
                if IsKind(name, kind) then
                    for lk, count in pairs(map) do
                        local zk = lk:match("^%-?%d+|(.+)$")
                        if zk and zk ~= "?" and ZoneValue(c, zk) == zone then sum[name] = (sum[name] or 0) + count end
                    end
                end
            end
        end
    end
    local list = {}
    for name, count in pairs(sum) do list[#list + 1] = { name, count } end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    while #list > n do table.remove(list) end
    return list
end

-- zones with kills: "All zones", then the zones and instances by name
function mod.KillZoneChoices(scope)
    local seen, list = {}, {}
    for _, c in ipairs(ScopeChars(scope)) do
        for _, map in pairs(c.killDetail or {}) do
            for lk in pairs(map) do
                local zk = lk:match("^%-?%d+|(.+)$")
                if zk and zk ~= "?" then
                    local value, text = ZoneValue(c, zk)
                    if not seen[value] then
                        seen[value] = true
                        list[#list + 1] = { value = value, text = text .. (value:sub(1, 2) == "i:" and " (instance)" or "") }
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.text < b.text end)
    table.insert(list, 1, { value = "ALL", text = "All zones" })
    return list
end

-- instances with at least one kill
function mod.JournalChoices(scope)
    local list = {}
    for _, e in ipairs(mod.KillZoneChoices(scope)) do
        if e.value:sub(1, 2) == "i:" then list[#list + 1] = { value = e.value, text = (e.text:gsub(" %(instance%)$", "")) } end
    end
    return list
end

-- the instance to show: the one picked this session, else the one the
-- character is in, else the last one visited, else the first with kills
function mod.JournalInstance(scope)
    local choices = mod.JournalChoices(scope)
    local valid = {}
    for _, e in ipairs(choices) do valid[e.value] = true end
    if mod.journalPick and valid[mod.journalPick] then return mod.journalPick end
    local zk, _, inst = mod.CurrentZone()   -- (Leveling.lua; not "x and f()": that keeps one value)
    if inst and zk then return zk end
    local c = mod.Char()
    local runs = c and c.runs or {}
    for i = #runs, 1, -1 do
        local key = "i:" .. tostring(runs[i].map)
        if valid[key] then return key end
    end
    return choices[1] and choices[1].value or nil
end

-- visits and bosses of an instance: { visits, last, bosses = { {name, kills, deaths} } }
function mod.Journal(scope, inst)
    local map = tonumber(inst:match("^i:(%d+)$"))
    local j = { visits = 0, last = 0, bosses = {} }
    local byName = {}
    local function Boss(name)
        local b = byName[name]
        if not b then b = { name = name, kills = 0, deaths = 0 } byName[name] = b; j.bosses[#j.bosses + 1] = b end
        return b
    end
    for name, n in pairs(Npcs()) do
        if (n.d or n.rb) and n.z == inst then Boss(name) end
    end
    for _, c in ipairs(ScopeChars(scope)) do
        for _, r in ipairs(c.runs or {}) do
            if r.map == map then
                j.visits = j.visits + 1
                j.last = math.max(j.last, r.enter or 0)
            end
        end
        for field, key in pairs({ killDetail = "kills", deathDetail = "deaths" }) do
            for name, m in pairs(c[field] or {}) do
                local nk = Npcs()[name]
                if nk and (nk.d or nk.rb) then
                    for lk, count in pairs(m) do
                        if lk:match("|(.+)$") == inst then local b = Boss(name) b[key] = b[key] + count end
                    end
                end
            end
        end
    end
    table.sort(j.bosses, function(a, b) if a.kills ~= b.kills then return a.kills > b.kills end return a.name < b.name end)
    return j
end

-- debug report lines
function mod.KillTypesReport(add)
    local n = { all = 0, rare = 0, d = 0, b = 0, rb = 0, cr = 0 }
    for _, x in pairs(Npcs()) do
        n.all = n.all + 1
        if x.c == "rare" or x.c == "rareelite" then n.rare = n.rare + 1 end
        if x.d then n.d = n.d + 1 end
        if x.b then n.b = n.b + 1 end
        if x.rb then n.rb = n.rb + 1 end
        if x.cr then n.cr = n.cr + 1 end
    end
    add(("  npc kinds known: %d (rare %d, dungeon boss %d, big baddie %d of them raid bosses %d, critter %d); last encounter: %s; in raid: %s"):format(
        n.all, n.rare, n.d, n.b, n.rb, n.cr, tostring(lastEncounter), tostring(InRaid() and true or false)))
    local t = mod.KillTotals("CHAR")
    add(("  this character: kills %d (rare %d, dungeon boss %d, big baddie %d, critter %d), deaths %d (gravity %d)"):format(
        t.all, t.rare, t.dboss, t.big, t.critter, t.deaths, t.gravity))
end
