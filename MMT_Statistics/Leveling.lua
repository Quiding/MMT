-- MMT Statistics: levels, zones and instances of this account's characters.
--
-- Per character record (Module.lua Store().chars[key]):
--   levels[L] = { start, done, t = seconds played on L, q = quests completed,
--                 k = NPCs killed, d = deaths, z = { [zoneKey] = seconds },
--                 partial = true while L was already running when tracking began }
--   zones[zoneKey] = { n = name, inst = true for instances, t, k, d, q, xp }
--   runs = { { map = instance map ID, n = name, uid = instance copy ID,
--              enter, leave, t, k, d, q, xp, cp = money gained,
--              lvIn / lvOut = character level on entering / leaving,
--              zn = the zone the character came from (the entrance) }, ... }   newest last, at most 300
--   killDetail[npc] = { ["<level>|<zoneKey>"] = count }   (also deathDetail)
-- Zone keys: "z:<uiMapID>" (the main zone: Goldshire counts as Elwynn Forest),
-- "i:<instanceMapID>" (every dungeon / raid / battleground its own zone),
-- "n:<name>" when the map API has nothing.
-- Instance copies: the 5th part of a creature GUID inside an instance (as
-- NovaInstanceTracker reads it: Creature-0-server-map-copyID-npcID-spawn);
-- entering the same copy again continues its run. WoW: Forever hides those
-- GUIDs inside instances: then every entry starts a new row, and when the
-- same instance was left within 3 hours (no reset since) the player is asked
-- whether it is the same copy ("Same instance" merges the rows).
-- Time counts every 5 s while logged in (gaps over 30 s, e.g. a frozen
-- client, count as 30 s).

local _, mod = ...
local MMT = MMT
local M = mod.M

local Safe, IsSecret = MMT.Safe, MMT.IsSecret
local function Plain(v) if v == nil or IsSecret(v) then return nil end return v end

mod.MAX_TRACKED_LEVEL = 59
local MAX_RUNS = 300
local MERGE_GAP = 3 * 3600   -- the same instance copy within 3 hours: one run
local ASK_GAP = 3 * 3600   -- re-entered within 3 hours, no reset: ask whether it is the same copy

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------
local function Level()
    return tonumber(Plain(Safe(UnitLevel, "player"))) or 0
end

local function LevelRec(c, L, fresh)
    c.levels = c.levels or {}
    local r = c.levels[L]
    if not r then
        r = { start = time(), t = 0, q = 0, k = 0, d = 0, z = {}, partial = not fresh or nil }
        c.levels[L] = r
    end
    r.z = r.z or {}
    return r
end

---------------------------------------------------------------------------
-- The zone the character is in
---------------------------------------------------------------------------
local zoneKey, zoneName, zoneInst, instMap

local ZONE_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

local function ReadZone()
    local inInstance, kind = Safe(IsInInstance)
    if inInstance and kind and kind ~= "none" then
        -- (MMT.Safe returns at most 7 values: the map ID is the 8th)
        local ok, name, _, _, _, _, _, _, mapID = pcall(GetInstanceInfo)
        if not ok then name, mapID = nil, nil end
        mapID, name = tonumber(Plain(mapID)), Plain(name)
        if mapID then return "i:" .. mapID, name or ("Instance " .. mapID), true, mapID end
    end
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local id = tonumber(Plain(Safe(C_Map.GetBestMapForUnit, "player")))
        local info = id and Safe(C_Map.GetMapInfo, id)
        -- micro maps (towns, caves) and dungeon floors belong to their zone
        local guard = 0
        while type(info) == "table" and (info.mapType or 0) > ZONE_TYPE and (info.parentMapID or 0) > 0 and guard < 6 do
            local parent = Safe(C_Map.GetMapInfo, info.parentMapID)
            if type(parent) ~= "table" or (parent.mapType or 0) < ZONE_TYPE then break end
            id, info, guard = info.parentMapID, parent, guard + 1
        end
        if type(info) == "table" and Plain(info.name) and info.name ~= "" then return "z:" .. id, info.name, false end
    end
    local name = Plain(Safe(GetRealZoneText)) or Plain(Safe(GetZoneText))
    if name and name ~= "" then return "n:" .. name, name, false end
    return nil
end

local run   -- the instance run this character is in now
local lastLand   -- the last zone outside instances (where the entrance is)
local reloading         -- PLAYER_ENTERING_WORLD said: UI reload
local sessionZoneRead   -- the zone was read once since this UI loaded
local said = {}   -- debug: each instance-copy reason once per instance entry

local function UpdateZone()
    local c = mod.Char()
    if not c then return end
    local key, name, inst, map = ReadZone()
    zoneKey, zoneName, zoneInst, instMap = key, name, inst, map
    if key and not inst then lastLand = name end
    if key then
        c.zones = c.zones or {}
        local z = c.zones[key] or { t = 0, k = 0, d = 0, q = 0, xp = 0 }
        z.n, z.inst = name, inst or nil
        c.zones[key] = z
    end
    -- instance runs
    c.runs = c.runs or {}
    if inst then
        if not run or run.map ~= map then
            if run then run.leave, run.lvOut = time(), Level() end
            -- every entry starts a new row (WoW: Forever hides the instance copy ID);
            -- when the last row is the same instance, left within 3 hours and not
            -- reset since, the player is asked whether it is the same copy (as
            -- NovaInstanceTracker does) and the rows are merged on "Same instance".
            -- After a /reload (or a relog within 2 minutes) in the instance it is
            -- the same one without asking, unless it was left over an hour ago.
            local last = c.runs[#c.runs]
            local sameMap = last and last.map == map and last.leave and not last.reset
            local firstRead = not sessionZoneRead
            if sameMap and firstRead and (time() - last.leave) < 3600
                and (reloading or (time() - last.leave) < 120) then
                run = last
                run.leave = nil
                M:Debug("instance: back in %s after a reload: same instance", tostring(name))
                mod.InstanceNote(("Back in %s after a reload: same instance (%s)."):format(tostring(name), mod.RunLabel(run)))
            else
                run = { map = map, n = name, enter = time(), t = 0, k = 0, d = 0, q = 0, xp = 0, lvIn = Level(), zn = lastLand }
                table.insert(c.runs, run)
                while #c.runs > MAX_RUNS do table.remove(c.runs, 1) end
                M:Debug("instance entered: %s (%d)", tostring(name), map)
                mod.journalPick = nil   -- the Dungeon Journal shows this instance again
                local ask = sameMap and time() - last.leave < ASK_GAP and M.db.askSameInstance ~= false
                mod.InstanceNote(("Entered %s: %s (%s). %s"):format(tostring(name),
                    ask and "a new instance unless you answer \"Same instance\"" or "new instance",
                    mod.RunLabel(run), mod.HourText()))
                if ask then
                    local new = run
                    C_Timer.After(2, function() mod.AskSameInstance(last, new) end)
                end
            end
            run.seenAt = time()   -- the copy ID is checked again after each entry
            run.checked = nil
            for k in pairs(said) do said[k] = nil end
        end
    elseif run then
        run.leave, run.lvOut = time(), Level()
        run = nil
    end
    if key then sessionZoneRead = true end
end
mod.UpdateZone = UpdateZone
function mod.LevelNow() return Level() end
-- as after a UI reload (test harness)
function mod.ForgetSession() run, sessionZoneRead = nil, nil end

function mod.CurrentZone() return zoneKey, zoneName, zoneInst end

-- the instance copy from a creature GUID; the same copy as an earlier run
-- (re-entered, relogged) continues that run
local function Why(reason, ...)
    if said[reason] then return end
    said[reason] = true
    M:Debug("instance copy: " .. reason, ...)
end
---------------------------------------------------------------------------
-- The hourly instance limit (5 per hour, every instance, the whole account)
---------------------------------------------------------------------------
mod.INSTANCES_PER_HOUR = 5

-- first entries of instance copies within the last hour, all characters of
-- this account, oldest first
function mod.InstancesLastHour()
    local list, since = {}, time() - 3600
    for _, c in pairs(mod.Store().chars) do
        for _, r in ipairs(c.runs or {}) do
            if (r.enter or 0) > since then list[#list + 1] = r.enter end
        end
    end
    table.sort(list)
    return list
end

function mod.HourText()
    local list = mod.InstancesLastHour()
    local n, cap = #list, mod.INSTANCES_PER_HOUR
    local text = ("Instances entered in the last hour: %d of %d."):format(n, cap)
    if n >= cap then
        text = text .. (" |cffff6666Limit reached:|r the next one can be entered at %s."):format(date("%H:%M", list[n - cap + 1] + 3600))
    elseif n == cap - 1 then
        text = text .. (" |cffffcc00One left;|r the next one frees up at %s."):format(date("%H:%M", list[1] + 3600))
    end
    return text
end

-- "#3": the character's visit number of that instance
function mod.RunLabel(r)
    if r.uid then return "ID " .. r.uid end
    local c = mod.Char()
    local n = 0
    for _, x in ipairs(c and c.runs or {}) do
        if x.map == r.map then n = n + 1 end
        if x == r then break end
    end
    return "#" .. n
end

function mod.InstanceNote(text)
    if M.db.instanceNotes == false then return end
    MMT.Print("Statistics: %s", text)
end

-- adds src's numbers to target and drops src; the current run follows
local function MergeRuns(target, src)
    local c = mod.Char()
    if not c or target == src then return end
    target.t, target.k = (target.t or 0) + (src.t or 0), (target.k or 0) + (src.k or 0)
    target.d, target.xp = (target.d or 0) + (src.d or 0), (target.xp or 0) + (src.xp or 0)
    target.q = (target.q or 0) + (src.q or 0)
    target.cp = (target.cp or 0) + (src.cp or 0)
    target.again = (target.again or 0) + 1 + (src.again or 0)
    target.leave = src.leave
    target.lvIn = target.lvIn or src.lvIn
    target.zn = target.zn or src.zn
    target.lvOut = src.lvOut or target.lvOut
    target.uid = target.uid or src.uid
    for j = #c.runs, 1, -1 do if c.runs[j] == src then table.remove(c.runs, j) end end
    if run == src then run = target; target.leave = nil end
    if mod.Redraw then mod.Redraw() end
end
mod.MergeRuns = MergeRuns

function mod.AskSameInstance(last, new)
    local c = mod.Char()
    if not c then return end
    local present = false
    for _, r in ipairs(c.runs) do if r == new then present = true end end
    if not present or new.uid then return end   -- merged meanwhile, or the copy ID decided
    MMT.UI.Confirm(("You entered %s again.\n\nIs this the same instance as your visit from %s? \"New instance\" keeps it as a separate row."):format(
            new.n or "the instance", date("%H:%M", last.enter or time())),
        "Same instance", function()
            MergeRuns(last, new)
            M:Debug("instance: merged with the visit from %s (player)", date("%H:%M", last.enter or 0))
            mod.InstanceNote(("%s: same instance as the visit from %s (%s). %s"):format(tostring(last.n),
                date("%H:%M", last.enter or 0), mod.RunLabel(last), mod.HourText()))
        end,
        "New instance")
end

local function SeeGUID(unit)
    if not run or run.checked then return end
    -- not MMT.Safe: it turns a secret value into nil, and the debug line
    -- should tell a hidden GUID from a missing one
    local ok, raw = pcall(UnitGUID, unit)
    if not ok or raw == nil then return end
    if IsSecret(raw) then Why("the game hides the GUIDs here (%s)", unit) return end
    if type(raw) ~= "string" then return end
    local kind, _, _, map, uid = strsplit("-", raw)
    if kind ~= "Creature" and kind ~= "Vehicle" then return end
    uid, map = tonumber(uid), tonumber(map)
    -- the copy ID is 0 outside instances; the map part of the GUID needn't be
    -- the instance's map ID on this client, so it isn't compared
    if not uid or uid <= 0 then
        Why("no copy ID in the GUID (map part %s, copy part %s)", tostring(map), tostring(uid))
        return
    end
    run.checked = true
    local c = mod.Char()
    run.uid = uid
    -- the same copy ID as an earlier visit (within 3 hours, no reset): merged without asking
    for i = #c.runs, 1, -1 do
        local r = c.runs[i]
        if r ~= run and r.map == run.map and r.uid == uid and not r.reset and (time() - (r.leave or r.enter)) < MERGE_GAP then
            MergeRuns(r, run)
            M:Debug("instance copy %d again: merged with the earlier visit", uid)
            return
        end
    end
    M:Debug("instance copy %d (map part of the GUID: %s, instance map %s)", uid, tostring(map), tostring(run.map))
end

-- "Deadmines has been reset.": the next entry is a new copy
local resetPattern
local function ResetPattern()
    if resetPattern == nil then
        local fmt = Plain(INSTANCE_RESET_SUCCESS)
        resetPattern = type(fmt) == "string"
            and ("^" .. fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%s", "(.+)") .. "$") or false
    end
    return resetPattern
end
M:On("CHAT_MSG_SYSTEM", function(msg)
    msg = Plain(msg)
    local p = ResetPattern()
    if type(msg) ~= "string" or not p then return end
    local name = msg:match(p)
    if not name then return end
    local c = mod.Char()
    for _, r in ipairs(c and c.runs or {}) do
        if r ~= run and r.n == name then r.reset = true end
    end
    M:Debug("instance reset: %s", name)
end)

---------------------------------------------------------------------------
-- Time
---------------------------------------------------------------------------
local lastTick
-- level: the level the time since the last tick belongs to (default: now)
local function Tick(level)
    local now = GetTime()
    local dt = lastTick and math.min(30, now - lastTick) or 0
    lastTick = now
    if dt <= 0 or not M.db.trackLeveling then return end
    local c = mod.Char()
    local L = level or Level()
    if not c or L < 1 then return end
    local lv = LevelRec(c, L)
    lv.t = (lv.t or 0) + dt
    if zoneKey then
        lv.z[zoneKey] = (lv.z[zoneKey] or 0) + dt
        local z = c.zones and c.zones[zoneKey]
        if z then z.t = (z.t or 0) + dt end
    end
    if run then run.t = (run.t or 0) + dt end
end

---------------------------------------------------------------------------
-- Experience
---------------------------------------------------------------------------
local xpLevel, xpCur, xpMax
local function ReadXP()
    return Level(), tonumber(Plain(Safe(UnitXP, "player"))) or 0, tonumber(Plain(Safe(UnitXPMax, "player"))) or 0
end

local function OnXP()
    local L, cur, max = ReadXP()
    local gained = 0
    if xpLevel then
        if L == xpLevel then gained = cur - xpCur
        elseif L == xpLevel + 1 then gained = (xpMax - xpCur) + cur end
    end
    xpLevel, xpCur, xpMax = L, cur, max
    if gained <= 0 or not M.db.trackLeveling then return end
    local c = mod.Char()
    if not c then return end
    local z = zoneKey and c.zones and c.zones[zoneKey]
    if z then z.xp = (z.xp or 0) + gained end
    if run then run.xp = (run.xp or 0) + gained end
end

---------------------------------------------------------------------------
-- Hooks from Kills.lua and Quests.lua
---------------------------------------------------------------------------
local function Detail(c, field, name)
    if not name then return end
    c[field] = c[field] or {}
    local d = c[field][name] or {}
    c[field][name] = d
    local k = Level() .. "|" .. (zoneKey or "?")
    d[k] = (d[k] or 0) + 1
end

function mod.OnKill(name)
    local c = mod.Char()
    if not c then return end
    Detail(c, "killDetail", name)
    if not M.db.trackLeveling then return end
    local L = Level()
    if L >= 1 then local lv = LevelRec(c, L) lv.k = (lv.k or 0) + 1 end
    local z = zoneKey and c.zones and c.zones[zoneKey]
    if z then z.k = (z.k or 0) + 1 end
    if run then run.k = (run.k or 0) + 1 end
end

-- killer: NPC name or nil (fell, drowned, a player, unknown)
function mod.OnDeath(killer)
    local c = mod.Char()
    if not c then return end
    Detail(c, "deathDetail", killer)
    if not M.db.trackLeveling then return end
    local L = Level()
    if L >= 1 then local lv = LevelRec(c, L) lv.d = (lv.d or 0) + 1 end
    local z = zoneKey and c.zones and c.zones[zoneKey]
    if z then z.d = (z.d or 0) + 1 end
    if run then run.d = (run.d or 0) + 1 end
end

-- returns the zone key for the quest record
function mod.OnQuestDone()
    local c = mod.Char()
    if not c or not M.db.trackLeveling then return zoneKey end
    local L = Level()
    if L >= 1 then local lv = LevelRec(c, L) lv.q = (lv.q or 0) + 1 end
    local z = zoneKey and c.zones and c.zones[zoneKey]
    if z then z.q = (z.q or 0) + 1 end
    if run then run.q = (run.q or 0) + 1 end   -- its XP comes with PLAYER_XP_UPDATE
    return zoneKey
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
M:On("PLAYER_LEVEL_UP", function(newLevel)
    newLevel = tonumber(Plain(newLevel))
    local c = mod.Char()
    if not c or not newLevel or not M.db.trackLeveling then return end
    Tick(newLevel - 1)   -- the time until now belongs to the old level
    local old = LevelRec(c, newLevel - 1)
    old.done = time()
    if c.levels[newLevel] and (c.levels[newLevel].t or 0) < 10 then c.levels[newLevel] = nil end
    LevelRec(c, newLevel, true)
    M:Debug("level %d reached (level %d took %d s)", newLevel, newLevel - 1, math.floor(old.t or 0))
    if mod.Redraw then mod.Redraw() end
end)
M:On("PLAYER_XP_UPDATE", function(unit) if unit == nil or unit == "player" then OnXP() end end)
-- money gained in an instance (loot, quest rewards; spending doesn't count)
local lastMoney
M:On("PLAYER_MONEY", function()
    local now = tonumber(Plain(Safe(GetMoney)))
    if not now then return end
    local gained = lastMoney and now - lastMoney or 0
    lastMoney = now
    if gained > 0 and run and M.db.trackLeveling then run.cp = (run.cp or 0) + gained end
end)
for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
    M:On(e, function() Tick() UpdateZone() end)
end
M:On("PLAYER_ENTERING_WORLD", function(initialLogin, reloadingUi)
    if reloadingUi == true then reloading = true end
    C_Timer.After(1, function() Tick() UpdateZone() reloading = nil end)
end)
M:On("PLAYER_TARGET_CHANGED", function() SeeGUID("target") end)
M:On("PLAYER_SOFT_ENEMY_CHANGED", function() SeeGUID("softenemy") end)
M:On("UPDATE_MOUSEOVER_UNIT", function() SeeGUID("mouseover") end)
M:On("NAME_PLATE_UNIT_ADDED", function(unit) if type(unit) == "string" then SeeGUID(unit) end end)
-- secret GUIDs can be readable out of combat: look again then
M:On("PLAYER_REGEN_ENABLED", function()
    C_Timer.After(1, function()
        SeeGUID("target")
        for i = 1, 40 do if run and not run.checked then SeeGUID("nameplate" .. i) end end
    end)
end)
M:On("PLAYER_LOGOUT", function() Tick() if run then run.leave, run.lvOut = time(), Level() end end)

local started
local function Start()
    if started then return end
    started = true
    xpLevel, xpCur, xpMax = ReadXP()
    lastMoney = tonumber(Plain(Safe(GetMoney)))
    UpdateZone()
    lastTick = GetTime()
    C_Timer.NewTicker(5, function() Tick() end)   -- (the ticker passes itself)
end
local oldEnable = M.OnEnable
M.OnEnable = function(...)
    if oldEnable then oldEnable(...) end
    C_Timer.After(2, Start)
end

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------
-- "dd:hh:mm:ss"
function mod.Duration(seconds)
    if not seconds then return "" end
    seconds = math.floor(seconds)
    return ("%02d:%02d:%02d:%02d"):format(math.floor(seconds / 86400), math.floor(seconds / 3600) % 24,
        math.floor(seconds / 60) % 60, seconds % 60)
end

local function FavZone(c, z)
    local best, bestT
    for key, t in pairs(z or {}) do
        if not bestT or t > bestT then best, bestT = key, t end
    end
    return best and (c.zones and c.zones[best] and c.zones[best].n or best:gsub("^%a:", ""))
end

-- "hh:mm:ss" (hours go past 24: "123:04:05")
function mod.Clock(seconds)
    if not seconds then return "" end
    seconds = math.floor(seconds)
    return ("%02d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

-- a character's levels in the compact form sent to the team:
-- { [L] = { t, q, k, d, z = favourite zone name, done = time or nil, p = partial } }
function mod.CompactLevels(c)
    local out = {}
    -- instances visited on a level: the runs entered at it
    local inst = {}
    for _, run in ipairs(c.runs or {}) do
        if run.lvIn then inst[run.lvIn] = (inst[run.lvIn] or 0) + 1 end
    end
    -- a level without an end while a higher one exists: its level-up wasn't
    -- recorded (addon or tracking off then); it ended when the next level
    -- began (e = 1: that end is taken from there)
    local top = 0
    for L in pairs(c.levels or {}) do if L > top then top = L end end
    for L, r in pairs(c.levels or {}) do
        if L >= 1 and L <= mod.MAX_TRACKED_LEVEL then
            local done, est = r.done, nil
            if not done and L < top then
                local nextL
                for L2, r2 in pairs(c.levels) do
                    if L2 > L and (not nextL or L2 < nextL) and r2.start then nextL = L2 end
                end
                done = nextL and c.levels[nextL].start or r.start or 0
                est = 1
            end
            out[L] = { t = math.floor(r.t or 0), q = r.q or 0, k = r.k or 0, d = r.d or 0,
                z = FavZone(c, r.z), done = done, e = est, p = r.partial and 1 or nil, i = inst[L] or 0 }
        end
    end
    return out
end

-- level rows of one character: { L, t, done, q, k, d, z, partial, current,
-- estimated (end taken from the next level's start), open (no end, not current) }
-- fill: also a row (missing = true) for every level from 1 up to the
-- character's level that has no record (MMT or tracking off then); key: the
-- character (its level counts when it is the one logged in)
function mod.CharLevelRows(c, fill, key)
    local rows = {}
    local lv = mod.CompactLevels(c)
    local top = 0
    if fill then
        for L in pairs(lv) do if L > top then top = L end end
        if key and MMT.IsSelf(key) then top = math.max(top, math.min(Level(), mod.MAX_TRACKED_LEVEL)) end
    end
    for L = mod.MAX_TRACKED_LEVEL, 1, -1 do
        local r = lv[L]
        if not r and fill and L <= top then
            rows[#rows + 1] = { L = L, missing = true, t = 0, q = 0, k = 0, d = 0, i = 0 }
        elseif r then
            -- only the highest level can be the current one
            local current = not r.done and #rows == 0
            rows[#rows + 1] = { L = L, t = r.t, done = r.done, q = r.q, k = r.k, d = r.d, z = r.z, i = r.i,
                partial = r.p ~= nil, current = current, estimated = r.e ~= nil, open = not r.done and not current }
        end
    end
    return rows
end

-- characters of a scope with their compact levels: list of { key, lv }
--   ACCOUNT: this account | TEAM: the team's characters | ALL: every account
function mod.LevelChars(scope)
    local list, seen = {}, {}
    local function Add(key, lv)
        if seen[key] or not lv or next(lv) == nil then return end
        seen[key] = true
        list[#list + 1] = { key, lv }
    end
    local own = mod.Store().chars
    if scope == "ACCOUNT" or scope == "ALL" then
        for key, c in pairs(own) do Add(key, mod.CompactLevels(c)) end
    end
    if scope == "ALL" then
        for _, a in pairs(mod.Store().accounts) do
            for key, c in pairs(a.chars or {}) do Add(key, c.lv) end
        end
    elseif scope == "TEAM" then
        local members = MMT.SortedMembers()
        local me = MMT.PlayerFull()
        if me then table.insert(members, 1, me) end
        for _, key in ipairs(members) do
            if own[key] then
                Add(key, mod.CompactLevels(own[key]))
            else
                local acc = mod.AccountOf(key)
                local a = acc and mod.Account(acc)
                local c = a and a.chars and a.chars[key]
                if c then Add(key, c.lv) end
            end
        end
    end
    return list
end

-- averages per level over the characters of a scope: levels finished (done)
-- count for the time; quests, kills and deaths average over the same
-- characters (all that have the level when none finished it yet).
-- Rows { L, t, n = characters, q, k, d, z = most common favourite zone }
function mod.AverageLevelRows(scope)
    local chars = mod.LevelChars(scope)
    local rows = {}
    for L = mod.MAX_TRACKED_LEVEL, 1, -1 do
        local done, any = {}, {}
        for _, e in ipairs(chars) do
            local r = e[2][L]
            if r then
                any[#any + 1] = r
                if r.done and not r.p then done[#done + 1] = r end
            end
        end
        local use = #done > 0 and done or any
        if #use > 0 then
            local t, q, k, d, inst, zones = 0, 0, 0, 0, 0, {}
            for _, r in ipairs(use) do
                t, q, k, d = t + (r.t or 0), q + (r.q or 0), k + (r.k or 0), d + (r.d or 0)
                inst = inst + (r.i or 0)   -- characters synced before 1.3.1 send no count: 0
                if r.z then zones[r.z] = (zones[r.z] or 0) + 1 end
            end
            local z, zn
            for name, n in pairs(zones) do if not zn or n > zn then z, zn = name, n end end
            rows[#rows + 1] = { L = L, t = #done > 0 and t / #done or nil, n = #use, q = q / #use,
                k = k / #use, d = d / #use, i = inst / #use, z = z }
        end
    end
    return rows
end
