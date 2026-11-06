-- MMT Statistics: CSV export (Settings tab > Export). Addons can't write
-- files, so the text goes into a box to copy (Ctrl+A, Ctrl+C) and paste into
-- a spreadsheet or a .csv file.
--   mod.ExportCSV(kind, scope, sep) -> text, rows
--   kind  GOLD_CHAR  gold per day and character (this account: other accounts
--                    only send their daily totals)
--         GOLD_ACC   gold per day and account
--         CHARS      one row per character: class, gold, kills, deaths, last seen
--         KILLS      NPCs killed and killed by (this account, per character)
--   scope TEAM | ACCOUNT | ALL | acc:<id> (as the tables)
--   sep   "," (decimal point) | ";" (decimal comma, e.g. German Excel)
--         QUESTS     quests of this account's characters (Quests.lua)
--         ZONES / INSTANCES  zones and instance visits of this account's characters (Leveling.lua)
--         LEVELING   one row per character and level, the data behind the Leveling tab
--                    (this account's raw records; other accounts what they sent)
--         KILL_SUMMARY / KILL_DETAIL / JOURNAL  the Kills tab (KillTypes.lua)
-- Names follow the privacy setting, like everything MMT shows.

local _, mod = ...
local MMT = MMT
local M = mod.M

mod.EXPORT_KINDS = {
    { value = "GOLD_CHAR", text = "Gold per day and character" },
    { value = "GOLD_ACC", text = "Gold per day and account" },
    { value = "CHARS", text = "Characters" },
    { value = "KILLS", text = "Kills and deaths (this account)" },
    { value = "KILL_SUMMARY", text = "Kill summary (this account)" },
    { value = "KILL_DETAIL", text = "Kills by zone and level (this account)" },
    { value = "JOURNAL", text = "Dungeon Journal (this account)" },
    { value = "QUESTS", text = "Quests (this account)" },
    { value = "ZONES", text = "Zones (this account)" },
    { value = "INSTANCES", text = "Instances (this account)" },
    { value = "LEVELING", text = "Leveling (per character and level)" },
}

local function Field(v, sep)
    v = tostring(v == nil and "" or v)
    if v:find('["\r\n]') or v:find(sep, 1, true) or v ~= v:match("^%s*(.-)%s*$") then
        v = '"' .. v:gsub('"', '""') .. '"'
    end
    return v
end

-- copper -> "1234.5678" gold (decimal comma with ";")
local function Gold(copper, sep)
    if not copper then return "" end
    copper = math.floor(copper)
    local text = ("%d.%04d"):format(math.floor(copper / 10000), copper % 10000)
    if sep == ";" then text = text:gsub("%.", ",") end
    return text
end

local function ClassName(class)
    return class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class or ""
end

local function Sorted(map, byValue)
    local list = {}
    for k, v in pairs(map or {}) do list[#list + 1] = { k, v } end
    table.sort(list, function(a, b)
        if byValue and a[2] ~= b[2] then return a[2] > b[2] end
        return tostring(a[1]) < tostring(b[1])
    end)
    return list
end

function mod.ExportCSV(kind, scope, sep)
    sep = sep == ";" and ";" or ","
    local lines = {}
    local function Row(...)
        local out = {}
        for i = 1, select("#", ...) do out[i] = Field((select(i, ...)), sep) end
        lines[#lines + 1] = table.concat(out, sep)
    end
    local ids = mod.ScopeAccounts(scope)
    local own = mod.AccountId()
    local s = mod.Store()

    if kind == "GOLD_CHAR" then
        Row("Date", "Account", "Character", "Class", "Gold", "Copper")
        for _, id in ipairs(ids) do
            if id == own then
                for _, e in ipairs(Sorted(s.chars)) do
                    local key, c = e[1], e[2]
                    for _, d in ipairs(Sorted(c.days)) do
                        Row(d[1], mod.AccountLabel(id), mod.CharName(key, c.class), ClassName(c.class),
                            Gold(d[2], sep), math.floor(d[2]))
                    end
                end
            end
        end
        table.sort(lines, function(a, b)
            if a:sub(1, 4) == "Date" then return true elseif b:sub(1, 4) == "Date" then return false end
            return a < b
        end)
    elseif kind == "GOLD_ACC" then
        Row("Date", "Account", "Gold", "Copper")
        local rows = {}
        for _, id in ipairs(ids) do
            local a = mod.Account(id)
            for d, v in pairs(a and a.days or {}) do
                rows[#rows + 1] = { d, mod.AccountLabel(id), v }
            end
        end
        table.sort(rows, function(x, y) if x[1] ~= y[1] then return x[1] < y[1] end return x[2] < y[2] end)
        for _, r in ipairs(rows) do Row(r[1], r[2], Gold(r[3], sep), math.floor(r[3])) end
    elseif kind == "CHARS" then
        Row("Account", "Character", "Class", "Gold", "Copper", "Kills", "Deaths", "Last seen")
        for _, id in ipairs(ids) do
            local a = mod.Account(id)
            for _, e in ipairs(Sorted(a and a.chars)) do
                local key, c = e[1], e[2]
                Row(mod.AccountLabel(id), mod.CharName(key, c.c), ClassName(c.c), Gold(c.g, sep),
                    c.g and math.floor(c.g) or "", c.k or "", c.d or "", c.s and date("%Y-%m-%d %H:%M", c.s) or "")
            end
        end
    elseif kind == "QUESTS" then
        Row("Account", "Character", "Quest ID", "Quest name", "Quest level", "Status",
            "Character level", "XP gained", "Copper gained", "Item rewards", "Accepted", "Completed / abandoned", "Source")
        local function When(t) return t and date("%Y-%m-%d %H:%M", t) or "" end
        for _, id in ipairs(ids) do
            if id == own then
                for _, e in ipairs(Sorted(s.chars)) do
                    local key, c = e[1], e[2]
                    local name = mod.CharName(key, c.class)
                    local qs = {}
                    for qid, q in pairs(c.quests or {}) do qs[#qs + 1] = { qid, q } end
                    table.sort(qs, function(a, b) return a[1] < b[1] end)
                    for _, qe in ipairs(qs) do
                        local qid, q = qe[1], qe[2]
                        Row(mod.AccountLabel(id), name, qid, q.n or "", q.l or "", mod.QUEST_STATUS[q.st] or "",
                            q.cl or "", q.xp or "", q.cp or "", mod.QuestItemsText(q.items, true),
                            When(q.ta), When(q.tc or q.tx), q.scan and "scan" or "tracked")
                    end
                end
            end
        end
    elseif kind == "LEVELING" then
        Row("Account", "Character", "Level", "Started", "Finished", "Finished from", "Shown as", "Partial",
            "Time played", "Seconds", "Quests", "Kills", "Deaths", "Instances", "Favourite zone")
        local function Date(t) return t and t > 0 and date("%Y-%m-%d %H:%M:%S", t) or "" end
        local function Rows(acc, key, class, lv, raw)
            local name = mod.CharName(key, class)
            local top
            local highest = 0
            for L in pairs(lv) do if L > highest then highest = L end end
            if MMT.IsSelf(key) then
                local cur = tonumber(UnitLevel and UnitLevel("player")) or 0
                if not MMT.IsSecret(cur) then highest = math.max(highest, math.min(cur, mod.MAX_TRACKED_LEVEL)) end
            end
            for L = mod.MAX_TRACKED_LEVEL, 1, -1 do
                local r = lv[L]
                if not r and L <= highest then
                    top = top or L
                    Row(acc, name, L, "", "", "", "no data recorded (was addon disabled?)", "", "", "", "", "", "", "", "")
                elseif r then
                    local shown = r.done and (r.e and "finished (level-up not recorded)" or "finished")
                        or (not top and "current" or "unknown end")
                    top = top or L
                    local rr = raw and raw[L]
                    Row(acc, name, L, Date(rr and rr.start), Date(r.done),
                        rr and (rr.done and "level-up" or (r.e and "next level start" or "")) or (r.e and "next level start" or (r.done and "level-up" or "")),
                        shown, r.p and "yes" or "no", mod.Clock(r.t or 0), math.floor(r.t or 0),
                        r.q or 0, r.k or 0, r.d or 0, r.i or 0, r.z or "")
                end
            end
        end
        for _, id in ipairs(ids) do
            if id == own then
                for _, e in ipairs(Sorted(s.chars)) do
                    local key, c = e[1], e[2]
                    Rows(mod.AccountLabel(id), key, c.class, mod.CompactLevels(c), c.levels)
                end
            else
                local a = mod.Account(id)
                for _, e in ipairs(Sorted(a and a.chars)) do
                    local key, c = e[1], e[2]
                    if c.lv then Rows(mod.AccountLabel(id), key, c.class, c.lv, nil) end
                end
            end
        end
    elseif kind == "ZONES" then
        Row("Account", "Character", "Zone", "Instance", "Time spent", "Seconds", "NPC kills", "Deaths",
            "Quests completed", "XP gain")
        for _, id in ipairs(ids) do
            if id == own then
                for _, e in ipairs(Sorted(s.chars)) do
                    local key, c = e[1], e[2]
                    local name = mod.CharName(key, c.class)
                    -- land zones by name (as the Zones tab), instances by key
                    local byKey, zs = {}, {}
                    for zk, z in pairs(c.zones or {}) do
                        local k = z.inst and zk or ("name:" .. tostring(z.n))
                        local sum = byKey[k]
                        if not sum then
                            sum = { n = z.n, inst = z.inst, t = 0, k = 0, d = 0, q = 0, xp = 0 }
                            byKey[k] = sum
                            zs[#zs + 1] = sum
                        end
                        for _, f in ipairs({ "t", "k", "d", "q", "xp" }) do sum[f] = sum[f] + (z[f] or 0) end
                    end
                    table.sort(zs, function(a, b) return (a.t or 0) > (b.t or 0) end)
                    for _, z in ipairs(zs) do
                        Row(mod.AccountLabel(id), name, z.n or "", z.inst and "yes" or "no", mod.Clock(z.t or 0),
                            math.floor(z.t or 0), z.k or 0, z.d or 0, z.q or 0, z.xp or 0)
                    end
                end
            end
        end
    elseif kind == "INSTANCES" then
        Row("Account", "Character", "Instance", "Zone", "Instance ID / visit", "Entered", "Exit", "Lvl In", "Lvl Out",
            "Time spent", "Seconds", "Kills", "Deaths", "Quests completed", "XP gain", "XP/hr", "Copper", "Copper/hr",
            "Entered again")
        local function When(t) return t and date("%Y-%m-%d %H:%M", t) or "" end
        local function Rate(v, t) if (t or 0) < 60 then return "" end return math.floor((v or 0) / (t / 3600) + 0.5) end
        for _, id in ipairs(ids) do
            if id == own then
                for _, e in ipairs(Sorted(s.chars)) do
                    local key, c = e[1], e[2]
                    local name = mod.CharName(key, c.class)
                    local nr = {}
                    for _, r in ipairs(c.runs or {}) do
                        nr[r.map or 0] = (nr[r.map or 0] or 0) + 1
                        Row(mod.AccountLabel(id), name, r.n or "", r.zn or "", r.uid or ("#" .. nr[r.map or 0]),
                            When(r.enter), When(r.leave), r.lvIn or "", r.lvOut or "", mod.Clock(r.t or 0), math.floor(r.t or 0),
                            r.k or 0, r.d or 0, r.q or 0, r.xp or 0, Rate(r.xp, r.t), r.cp or 0, Rate(r.cp, r.t), r.again or 0)
                    end
                end
            end
        end
    elseif kind == "KILL_SUMMARY" then
        Row("Account", "Character", "NPCs", "Rares", "Dungeon Bosses", "Big Baddies", "Critters", "Deaths",
            "By Gravity", "Unique instances visited", "Instance visits")
        for _, id in ipairs(ids) do
            if id == own then
                for _, e in ipairs(Sorted(s.chars)) do
                    local key, c = e[1], e[2]
                    local t = mod.KillTotals("char:" .. key)
                    Row(mod.AccountLabel(id), mod.CharName(key, c.class), t.all, t.rare, t.dboss, t.big, t.critter,
                        t.deaths, t.gravity, mod.UniqueInstances("char:" .. key), #(c.runs or {}))
                end
            end
        end
    elseif kind == "KILL_DETAIL" then
        Row("Account", "Character", "Type", "NPC", "Kind", "Zone", "Instance", "Character level", "Count")
        for _, id in ipairs(ids) do
            if id == own then
                for _, e in ipairs(Sorted(s.chars)) do
                    local key, c = e[1], e[2]
                    local name = mod.CharName(key, c.class)
                    for field, label in pairs({ killDetail = "Killed", deathDetail = "Killed by" }) do
                        for _, n in ipairs(Sorted(c[field])) do
                            for _, d in ipairs(Sorted(n[2])) do
                                local level, zk = tostring(d[1]):match("^(%-?%d+)|(.+)$")
                                local z = zk and c.zones and c.zones[zk]
                                Row(mod.AccountLabel(id), name, label, n[1], mod.NpcKindText(n[1]),
                                    z and z.n or (zk ~= "?" and zk or ""), z and z.inst and "yes" or "no", level or "", d[2])
                            end
                        end
                    end
                end
            end
        end
    elseif kind == "JOURNAL" then
        Row("Account", "Instance", "Unique instances visited", "Visits", "Last visit", "NPCs killed", "Boss kills", "Boss", "Kind", "Killed", "Killed me")
        -- the whole account (or the scope's characters: all of this account)
        if mod.AccountId() and (function() for _, id in ipairs(ids) do if id == own then return true end end end)() then
            local uniq = mod.UniqueInstances("ACCOUNT")
            for _, inst in ipairs(mod.JournalChoices("ACCOUNT")) do
                local j = mod.Journal("ACCOUNT", inst.value)
                local last = j.last > 0 and date("%Y-%m-%d %H:%M", j.last) or ""
                if #j.bosses == 0 then
                    Row(mod.AccountLabel(own), inst.text, uniq, j.visits, last, j.npcs, j.bossKills, "", "", "", "")
                end
                for _, b in ipairs(j.bosses) do
                    Row(mod.AccountLabel(own), inst.text, uniq, j.visits, last, j.npcs, j.bossKills, b.name, mod.NpcKindText(b.name), b.kills, b.deaths)
                end
            end
        end
    elseif kind == "KILLS" then
        Row("Account", "Character", "Type", "NPC", "Kind", "Count")
        for _, id in ipairs(ids) do
            local label = mod.AccountLabel(id)
            if id == own then
                for _, e in ipairs(Sorted(s.chars)) do
                    local key, c = e[1], e[2]
                    local name = mod.CharName(key, c.class)
                    for _, k in ipairs(Sorted(c.kills, true)) do Row(label, name, "Killed", k[1], mod.NpcKindText(k[1]), k[2]) end
                    for _, k in ipairs(Sorted(c.deaths, true)) do Row(label, name, "Killed by", k[1], mod.NpcKindText(k[1]), k[2]) end
                end
            end   -- other accounts keep their kills (not sent to the team)
        end
    end
    return table.concat(lines, "\n"), #lines - 1
end

---------------------------------------------------------------------------
-- Backup / import: this account's statistics as one text (another computer,
-- a reinstalled client). Unlike the CSV it keeps everything: real names,
-- gold per day, kills, deaths and quests of every character.
--   "MMTSTATS1:" .. packed serialized { v = 1, chars = { [key] = record } }
-- Import merges into this account: nothing recorded here is lost.
---------------------------------------------------------------------------
local BACKUP_TAG = "MMTSTATS1:"

function mod.BackupText()
    local chars = {}
    for key, c in pairs(mod.Store().chars) do chars[key] = c end
    return BACKUP_TAG .. MMT.Pack(MMT.Serialize({ v = 1, at = time(), chars = chars }))
end

local function MaxMap(dst, src)
    for k, v in pairs(src or {}) do
        if type(v) == "number" and (dst[k] or 0) < v then dst[k] = v end
    end
end

-- returns characters, gold days, quests added (or nil and an error)
function mod.ImportBackup(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text:sub(1, #BACKUP_TAG) ~= BACKUP_TAG then return nil, "That text is not an MMT Statistics backup." end
    local plain = MMT.Unpack(text:sub(#BACKUP_TAG + 1))
    local t = plain and MMT.Deserialize(plain)
    if type(t) ~= "table" or type(t.chars) ~= "table" then return nil, "The backup could not be read (incomplete copy?)." end
    local s = mod.Store()
    local nChars, nDays, nQuests = 0, 0, 0
    for key, src in pairs(t.chars) do
        if type(key) == "string" and type(src) == "table" then
            local c = s.chars[key]
            if not c then
                c = { days = {}, kills = {}, deaths = {}, killTotal = 0, deathTotal = 0 }
                s.chars[key] = c
                nChars = nChars + 1
            end
            c.acc = s.accountId   -- counts for this account from now on
            c.class = c.class or src.class
            c.gold = c.gold or src.gold
            if (src.seen or 0) > (c.seen or 0) then c.seen = src.seen; c.gold = src.gold or c.gold end
            c.days = c.days or {}
            for d, v in pairs(src.days or {}) do
                if c.days[d] == nil then c.days[d] = v; nDays = nDays + 1 end   -- recorded here wins
            end
            -- kills / deaths: the higher count (a reinstall starts again from 0)
            c.kills, c.deaths = c.kills or {}, c.deaths or {}
            MaxMap(c.kills, src.kills)
            MaxMap(c.deaths, src.deaths)
            local kt, dt = 0, 0
            for _, n in pairs(c.kills) do kt = kt + n end
            for _, n in pairs(c.deaths) do dt = dt + n end
            c.killTotal = math.max(kt, c.killTotal or 0, src.killTotal or 0)
            c.deathTotal = math.max(dt, c.deathTotal or 0, src.deathTotal or 0)
            -- levels, zones, instance runs, kill / death details (1.0.18)
            c.levels = c.levels or {}
            for L, r in pairs(src.levels or {}) do if c.levels[L] == nil then c.levels[L] = r end end
            c.zones = c.zones or {}
            for zk, z in pairs(src.zones or {}) do
                local mine = c.zones[zk]
                if not mine then c.zones[zk] = z
                else
                    for _, f in ipairs({ "t", "k", "d", "q", "xp" }) do
                        if (z[f] or 0) > (mine[f] or 0) then mine[f] = z[f] end
                    end
                end
            end
            c.runs = c.runs or {}
            local haveRun = {}
            for _, r in ipairs(c.runs) do haveRun[(r.map or 0) .. ":" .. (r.enter or 0)] = true end
            for _, r in ipairs(src.runs or {}) do
                if not haveRun[(r.map or 0) .. ":" .. (r.enter or 0)] then table.insert(c.runs, r) end
            end
            table.sort(c.runs, function(a, b) return (a.enter or 0) < (b.enter or 0) end)
            for _, field in ipairs({ "killDetail", "deathDetail" }) do
                c[field] = c[field] or {}
                for npc, map in pairs(src[field] or {}) do
                    c[field][npc] = c[field][npc] or {}
                    MaxMap(c[field][npc], map)
                end
            end
            -- quests: a tracked record beats a scanned one, else the one here
            c.quests = c.quests or {}
            for qid, q in pairs(src.quests or {}) do
                local mine = c.quests[qid]
                if type(q) == "table" then
                    if not mine or (mine.scan and not q.scan) then
                        c.quests[qid] = q
                        if not mine then nQuests = nQuests + 1 end
                    else
                        mine.n, mine.l = mine.n or q.n, mine.l or q.l
                    end
                end
            end
        end
    end
    -- the chart keeps 60 days
    local first = mod.Days()[1]
    for _, c in pairs(s.chars) do
        for d in pairs(c.days or {}) do if d < first then c.days[d] = nil end end
    end
    mod.SendSoon()
    if mod.Redraw then mod.Redraw() end
    return nChars, nDays, nQuests
end
