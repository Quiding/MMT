-- MMT Statistics: NPCs killed and NPCs that killed this character.
--
-- WoW: Forever hides some combat information from addons (secret values),
-- and the combat log is reserved for the Blizzard UI (registering
-- COMBAT_LOG_EVENT_UNFILTERED gets the addon blocked). So kills come from:
--   1. NPCs this character was in combat with (threat) that die while they
--      are its target or have a nameplate, and that it (or its group) tapped,
--   1b. the target dying (PLAYER_TARGET_DIED), also for NPCs without experience,
--   1c. NPCs with a nameplate that die tapped by this character or its group,
--       dungeon encounters won, and kills a team member near you reports
--       (KillTypes.lua and below),
--   2. the experience message "X dies, you gain N experience.".
-- A kill seen by both counts once.
-- The killer at death: the hostile target that targets this character, else
-- an NPC nameplate that does.

local _, mod = ...
local MMT = MMT
local M = mod.M

local Safe, IsSecret = MMT.Safe, MMT.IsSecret
local sources = { threat = 0, target = 0, team = 0, nameplate = 0, encounter = 0, xp = 0, deaths = 0 }   -- debug report
local recent = {}       -- [name] = { t, guid }: the same kill from another source
local engaged = {}      -- [guid] = name: NPCs in combat with this character

local function Plain(v) if v == nil or IsSecret(v) then return nil end return v end
mod.UNKNOWN_NPC = "(unknown NPC)"   -- a kill whose name the game kept hidden

local function IsNPCGuid(guid)
    guid = Plain(guid)
    if type(guid) ~= "string" then return false end
    local kind = guid:match("^(%a+)%-")
    return kind == "Creature" or kind == "Vehicle"
end

local function Count(name, guid, source)
    name = Plain(name)
    if type(name) ~= "string" or name == "" or not M.db.trackKills then return end
    guid = Plain(guid)
    local now = GetTime()
    local r = recent[name]
    if name ~= mod.UNKNOWN_NPC and r and now - r.t < 3 and (not guid or not r.guid or guid == r.guid) then return false end
    recent[name] = { t = now, guid = guid }
    local c = mod.Char()
    if not c then return end
    c.kills[name] = (c.kills[name] or 0) + 1
    c.killTotal = (c.killTotal or 0) + 1
    if mod.OnKill then mod.OnKill(name) end   -- level / zone / instance (Leveling.lua)
    if mod.OnEncounterKill then mod.OnEncounterKill(name) end   -- an encounter's boss (KillTypes.lua)
    sources[source] = sources[source] + 1
    M:Debug("kill %s (%s): %s", name, source, mod.NpcKindText and mod.NpcKindText(name) or "?")
    if mod.Redraw then mod.Redraw() end
    return true
end

-- for KillTypes.lua (nameplate kills, encounters)
function mod.CountKill(name, source) return Count(name, nil, source) end

---------------------------------------------------------------------------
-- 1. Threat: NPCs in combat with this character that die
---------------------------------------------------------------------------
local function Watch(unit)
    if not M.db.trackKills or not Safe(UnitExists, unit) or Safe(UnitIsPlayer, unit) then return end
    local guid = Safe(UnitGUID, unit)
    if not IsNPCGuid(guid) then return end
    if Safe(UnitIsDead, unit) then
        local name = engaged[guid]
        if name then
            engaged[guid] = nil
            -- only kills this character or its group tapped
            if not Safe(UnitIsTapDenied, unit) then Count(name, guid, "threat") end
        end
        return
    end
    local threat = Safe(UnitThreatSituation, "player", unit)
    if threat then
        local name = Safe(UnitName, unit)
        if name then engaged[guid] = name end
    end
end

M:On("UNIT_THREAT_LIST_UPDATE", function(unit) if unit then Watch(unit) end end)
M:On("UNIT_HEALTH", function(unit)
    if unit == "target" or (type(unit) == "string" and unit:match("^nameplate")) then Watch(unit) end
end)
M:On("PLAYER_TARGET_CHANGED", function() Watch("target") end)
M:On("NAME_PLATE_UNIT_ADDED", function(unit) Watch(unit) end)
M:On("NAME_PLATE_UNIT_REMOVED", function(unit) Watch(unit) end)
-- forget old fights
M:On("PLAYER_REGEN_ENABLED", function()
    C_Timer.After(5, function()
        if not Safe(UnitAffectingCombat, "player") then wipe(engaged) end
    end)
end)

---------------------------------------------------------------------------
-- 1b. The target dies (PLAYER_TARGET_DIED): counts kills that give no
--     experience too (grey NPCs), and works when the game hides GUIDs and
--     threat in combat. Only NPCs this character or its group tapped.
---------------------------------------------------------------------------
local targetName   -- the target's name, read while it was readable
local TellTeam     -- below (1c)
local function ReadTarget()
    if not Safe(UnitExists, "target") then targetName = nil return end
    if Safe(UnitIsPlayer, "target") then targetName = nil return end
    local name = Plain(Safe(UnitName, "target"))
    targetName = (type(name) == "string" and name ~= "") and name or nil   -- nil: hidden (a new target)
end
M:On("PLAYER_TARGET_CHANGED", ReadTarget)
M:On("UNIT_NAME_UPDATE", function(unit)
    if unit ~= "target" then return end
    local name = Plain(Safe(UnitName, "target"))
    if type(name) == "string" and name ~= "" then targetName = name end
end)
-- diagnostics for the debug report
mod.killDiag = { targetDied = 0, hiddenName = 0, tapDenied = 0, late = 0, unknown = 0, plateDead = 0, plateHidden = 0 }
local D = mod.killDiag

local function TargetKill(name)
    if mod.LearnUnit then mod.LearnUnit("target") end
    if Count(name, Plain(Safe(UnitGUID, "target")), "target") then TellTeam(name) end
end

M:On("PLAYER_TARGET_DIED", function()
    if not M.db.trackKills then return end
    D.targetDied = D.targetDied + 1
    if Safe(UnitIsPlayer, "target") then return end
    if Safe(UnitIsTapDenied, "target") then D.tapDenied = D.tapDenied + 1 return end   -- someone else's
    local now = Plain(Safe(UnitName, "target"))
    local name = now or targetName
    if type(name) == "string" and name ~= "" then
        if not now then M:Debug("target died: name hidden now, using %s from before", name) end
        TargetKill(name)
        return
    end
    -- the game hides the name (inside instances in combat): read it again
    -- from the corpse a little later, else count an unknown NPC
    D.hiddenName = D.hiddenName + 1
    local diedAt = GetTime()
    if mod.TargetDiedAt then mod.TargetDiedAt(diedAt) end
    M:Debug("target died: name hidden, trying again")
    local tries = 0
    local function Again()
        tries = tries + 1
        local later = Plain(Safe(UnitName, "target"))
        if type(later) == "string" and later ~= "" and Safe(UnitIsDead, "target") then
            D.late = D.late + 1
            M:Debug("target died: name readable later: %s", later)
            TargetKill(later)
        elseif tries < 20 and Safe(UnitExists, "target") then
            C_Timer.After(0.5, Again)
        else
            -- the target that died when a boss fight ended is that boss (the
            -- encounter's name is the one name the game still tells)
            local boss, already
            if mod.EncounterBossAt then boss, already = mod.EncounterBossAt(diedAt) end
            if boss then
                M:Debug("target died: name hidden, but it died as the encounter %s ended: that boss%s", boss,
                    already and " (already counted)" or "")
                if not already then Count(boss, nil, "encounter") end
                return
            end
            D.unknown = D.unknown + 1
            M:Debug("target died: name stayed hidden, counted as an unknown NPC")
            Count(mod.UNKNOWN_NPC, nil, "target")
        end
    end
    C_Timer.After(0.5, Again)
end)

---------------------------------------------------------------------------
-- 1c. Kills the team saw: an NPC that gave no experience (grey) dies as
--     somebody's target; that client tells the team ("STK:<name>") and every
--     team member near it counts it too (a healer without that target). Kills
--     with experience need no message: everybody near gets the XP line.
---------------------------------------------------------------------------
local xpSeen = {}   -- [name] = GetTime() of the last experience line
TellTeam = function(name)
    if not IsInGroup() then return end
    C_Timer.After(1.5, function()
        if xpSeen[name] and GetTime() - xpSeen[name] < 3 then return end   -- it gave experience
        MMT.SendToTeam("STK:" .. name, true, "NORMAL")
    end)
end
mod.TellTeamKill = TellTeam

local function Near(key)
    local unit = MMT.UnitForMember and MMT.UnitForMember(key)
    if not unit then return false end
    if Safe(UnitInRange, unit) or Safe(CheckInteractDistance, unit, 4) or Safe(UnitIsVisible, unit) then return true end
    -- in the same instance: near enough
    local inInstance = Safe(IsInInstance)
    return inInstance and Safe(UnitIsConnected, unit) and not Safe(UnitIsDeadOrGhost, unit) and true or false
end

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local name = text:match("^STK:(.+)$")
    if not name or not M.db.trackKills then return end
    if not Near(key) then M:Debug("team kill %s by %s: too far away", name, MMT.Repr(key)) return end
    Count(name, nil, "team")
end)

---------------------------------------------------------------------------
-- 2. Experience message
---------------------------------------------------------------------------
local xpPattern
local function XPPattern()
    if xpPattern ~= nil then return xpPattern end
    local fmt = COMBATLOG_XPGAIN_FIRSTPERSON   -- "%s dies, you gain %d experience."
    if type(fmt) ~= "string" then xpPattern = false return false end
    local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("%%s", "(.+)", 1):gsub("%%d", "%%d+")
    xpPattern = "^" .. p
    return xpPattern
end

M:On("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
    msg = Plain(msg)
    local p = XPPattern()
    if type(msg) ~= "string" or not p then return end
    local name = msg:match(p)
    if name then xpSeen[name] = GetTime() Count(name, nil, "xp") end
end)

---------------------------------------------------------------------------
-- Deaths: who killed this character
---------------------------------------------------------------------------
local function TargetsMe(unit)
    return Safe(UnitExists, unit) and not Safe(UnitIsPlayer, unit) and Safe(UnitCanAttack, "player", unit)
        and Safe(UnitIsUnit, unit .. "target", "player")
end

local function Killer()
    if TargetsMe("target") then return Safe(UnitName, "target") end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if TargetsMe(unit) then return Safe(UnitName, unit) end
    end
end

M:On("PLAYER_DEAD", function()
    if not M.db.trackKills then return end
    local name = Plain(Killer())
    -- every death counts for the level / zone; the killer only when an NPC is known
    if mod.OnDeath then mod.OnDeath(name) end
    if not name then return end   -- fell, drowned, a player, or unknown: no killer
    local c = mod.Char()
    if not c then return end
    c.deaths[name] = (c.deaths[name] or 0) + 1
    c.deathTotal = (c.deathTotal or 0) + 1
    sources.deaths = sources.deaths + 1
    M:Debug("killed by %s", name)
    if mod.Redraw then mod.Redraw() end
end)

---------------------------------------------------------------------------
-- Scopes: totals and top lists of the accounts of a scope
---------------------------------------------------------------------------
-- field "kills" | "deaths"; top n of the characters of a scope (this
-- account only) as { {name, count}, ... }
function mod.TopList(scope, field, n)
    local sum = {}
    for key, c in pairs(mod.Store().chars) do
        if mod.InScope(scope, key) then
            for name, count in pairs(c[field] or {}) do sum[name] = (sum[name] or 0) + count end
        end
    end
    local list = {}
    for name, count in pairs(sum) do list[#list + 1] = { name, count } end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    while #list > n do table.remove(list) end
    return list
end

function mod.KillReport(add)
    add(("  kill sources: threat %d, target died %d, nameplate %d, encounter %d, team %d, xp message %d; deaths %d; xp pattern %s"):format(
        sources.threat, sources.target, sources.nameplate, sources.encounter, sources.team, sources.xp, sources.deaths, tostring(XPPattern())))
    add(("  target died events %d: name hidden %d (read later %d, unknown %d), tapped by others %d; nameplate deaths %d (name hidden %d)"):format(
        D.targetDied, D.hiddenName, D.late, D.unknown, D.tapDenied, D.plateDead, D.plateHidden))
    if mod.KillTypesReport then mod.KillTypesReport(add) end
end
