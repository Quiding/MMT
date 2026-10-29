-- MMT Statistics: NPCs killed and NPCs that killed this character.
--
-- WoW: Forever hides some combat information from addons (secret values),
-- and the combat log is reserved for the Blizzard UI (registering
-- COMBAT_LOG_EVENT_UNFILTERED gets the addon blocked). So kills come from:
--   1. NPCs this character was in combat with (threat) that die while they
--      are its target or have a nameplate, and that it (or its group) tapped,
--   2. the experience message "X dies, you gain N experience.".
-- A kill seen by both counts once.
-- The killer at death: the hostile target that targets this character, else
-- an NPC nameplate that does.

local _, mod = ...
local MMT = MMT
local M = mod.M

local Safe, IsSecret = MMT.Safe, MMT.IsSecret
local sources = { threat = 0, xp = 0, deaths = 0 }   -- debug report
local recent = {}       -- [name] = { t, guid }: the same kill from another source
local engaged = {}      -- [guid] = name: NPCs in combat with this character

local function Plain(v) if v == nil or IsSecret(v) then return nil end return v end

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
    if r and now - r.t < 3 and (not guid or not r.guid or guid == r.guid) then return end
    recent[name] = { t = now, guid = guid }
    local c = mod.Char()
    if not c then return end
    c.kills[name] = (c.kills[name] or 0) + 1
    c.killTotal = (c.killTotal or 0) + 1
    sources[source] = sources[source] + 1
    M:Debug("kill %s (%s)", name, source)
    mod.SendSoon(60)
    if mod.Redraw then mod.Redraw() end
end

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
    if name then Count(name, nil, "xp") end
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
    if not name then return end   -- fell, drowned, a player, or unknown: not counted
    local c = mod.Char()
    if not c then return end
    c.deaths[name] = (c.deaths[name] or 0) + 1
    c.deathTotal = (c.deathTotal or 0) + 1
    sources.deaths = sources.deaths + 1
    M:Debug("killed by %s", name)
    mod.SendSoon(30)
    if mod.Redraw then mod.Redraw() end
end)

---------------------------------------------------------------------------
-- Scopes: totals and top lists of the accounts of a scope
---------------------------------------------------------------------------
-- field "kills" | "deaths"; top n as { {name, count}, ... }
function mod.TopList(scope, field, n)
    local sum = {}
    for _, id in ipairs(mod.ScopeAccounts(scope)) do
        local a = mod.Account(id)
        for name, count in pairs(a and a[field] or {}) do sum[name] = (sum[name] or 0) + count end
    end
    local list = {}
    for name, count in pairs(sum) do list[#list + 1] = { name, count } end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    while #list > n do table.remove(list) end
    return list
end

function mod.KillReport(add)
    add(("  kill sources: threat %d, xp message %d; deaths %d; xp pattern %s"):format(
        sources.threat, sources.xp, sources.deaths, tostring(XPPattern())))
end
