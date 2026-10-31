-- MMT module: Statistics.
--
-- Gold: every character on this WoW account that logs in with MMT records
-- its gold (after login and on every change; not at logout: 0 there) in the module's
-- account-wide store, so it doesn't depend on the profile. One record per
-- day and character, kept for 60 days.
--
-- Accounts: each WoW account has its own saved variables, so the store is
-- the account. It gets a random id once. Every client sends a summary of its
-- account to the team (characters with gold and kills, the daily total of
-- the account, its top kills and killers); the others keep the latest one
-- per account, together with the team member that sent it ("account of X").
--
-- Messages (long texts via MMT.SendLong, compressed when the client can;
-- never in combat, at most every few minutes: see "Sending" below):
--   STA:<packed summary>   this account's summary
--   STQ                    please send your summary
--
-- Kills and deaths: see Kills.lua.

local _, mod = ...
local MMT = MMT

local M = MMT.NewModule({
    name = "Statistics",
    title = "Statistics",
    description = "Gold of every character and account over 60 days, NPCs killed and what killed you.",
    sync = true,
    syncExclude = { "chartScope", "killScope" },
    defaults = {
        trackGold   = true,
        trackKills  = true,
        share       = true,     -- send and receive account summaries
        money       = "SHORT",  -- SHORT 5g 32s 1c | GOLD 5g | COINS icons
        chartScope  = "TEAM",   -- TEAM | ACCOUNT | ALL | acc:<id>
        killScope   = "TEAM",
        sendEvery   = 5,        -- minutes: at most one summary per this time
    },
})
mod.M = M
mod.DAYS = 60

---------------------------------------------------------------------------
-- Store
---------------------------------------------------------------------------
-- M.store.accountId, .chars[key], .accounts[id], .memberAccount[teamKey]
local function Store()
    local s = M.store
    if not s.accountId then
        s.accountId = ("%04x%04x"):format(math.random(0, 0xffff), math.random(0, 0xffff))
    end
    s.chars = s.chars or {}
    s.accounts = s.accounts or {}
    s.memberAccount = s.memberAccount or {}
    return s
end
mod.Store = Store

function mod.AccountId() return Store().accountId end

-- the 60 dates of the chart, oldest first ("2026-10-29")
function mod.Days()
    local t = date("*t")
    local noon = time({ year = t.year, month = t.month, day = t.day, hour = 12 })
    local list = {}
    for i = mod.DAYS - 1, 0, -1 do list[#list + 1] = date("%Y-%m-%d", noon - i * 86400) end
    return list
end

function mod.Today() return date("%Y-%m-%d") end

-- this character's record
function mod.Char(key)
    key = key or MMT.PlayerFull()
    if not key then return nil end
    local chars = Store().chars
    local c = chars[key]
    if not c then
        c = { days = {}, kills = {}, deaths = {}, killTotal = 0, deathTotal = 0 }
        chars[key] = c
    end
    c.days = c.days or {}
    c.kills = c.kills or {}
    c.deaths = c.deaths or {}
    c.killTotal = c.killTotal or 0
    c.deathTotal = c.deathTotal or 0
    return c
end

local function Prune(days, first)
    for d in pairs(days) do if d < first then days[d] = nil end end
end

---------------------------------------------------------------------------
-- Gold
---------------------------------------------------------------------------
function mod.RecordGold()
    if not (M.enabled and M.db.trackGold) then return end
    local key = MMT.PlayerFull()
    local c = key and mod.Char(key)
    if not c then return end
    local money = GetMoney and GetMoney()
    if not money or MMT.IsSecret(money) then return end
    local _, class = UnitClass("player")
    c.class = class or c.class
    c.gold = money
    c.seen = time()
    c.days[mod.Today()] = money
    Prune(c.days, mod.Days()[1])
end

-- value of a series on each of the chart's days: the last record on or before
-- that day (nil before the first record)
local function Carry(days, list)
    local out, last = {}, nil
    local earlier = nil
    for d, v in pairs(days or {}) do
        if d < list[1] and (not earlier or d > earlier) then earlier = d end
    end
    if earlier then last = days[earlier] end
    for i, d in ipairs(list) do
        if days[d] ~= nil then last = days[d] end
        out[i] = last
    end
    return out
end

-- daily total of this account: { [date] = copper } for the days with data
function mod.OwnDayTotals()
    local list = mod.Days()
    local sum, any = {}, {}
    for _, c in pairs(Store().chars) do
        local series = Carry(c.days, list)
        for i = 1, #list do
            if series[i] then sum[i] = (sum[i] or 0) + series[i]; any[i] = true end
        end
    end
    local out = {}
    for i, d in ipairs(list) do if any[i] then out[d] = sum[i] end end
    return out
end

---------------------------------------------------------------------------
-- Accounts: this one and the ones the team sent
---------------------------------------------------------------------------
local function Top(map, n)
    local list = {}
    for name, count in pairs(map) do list[#list + 1] = { name, count } end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    local out = {}
    for i = 1, math.min(n, #list) do out[list[i][1]] = list[i][2] end
    return out
end
mod.Top = Top

-- kills / deaths of all characters of this account together
local function OwnSums(field)
    local sum = {}
    for _, c in pairs(Store().chars) do
        for name, n in pairs(c[field] or {}) do sum[name] = (sum[name] or 0) + n end
    end
    return sum
end

-- this account in the same shape as a received one
function mod.OwnAccount()
    local chars = {}
    for key, c in pairs(Store().chars) do
        chars[key] = { c = c.class, g = c.gold, k = c.killTotal or 0, d = c.deathTotal or 0, s = c.seen }
    end
    return {
        id = mod.AccountId(), owner = MMT.PlayerFull(), own = true, at = time(),
        chars = chars, days = mod.OwnDayTotals(),
        kills = OwnSums("kills"), deaths = OwnSums("deaths"),
    }
end

function mod.Account(id)
    if id == mod.AccountId() then return mod.OwnAccount() end
    return Store().accounts[id]
end

-- account id of a team member (nil: never heard from)
function mod.AccountOf(key)
    if MMT.IsSelf(key) then return mod.AccountId() end
    return Store().memberAccount[key]
end

-- all known accounts, this one first
function mod.AccountIds()
    local ids = { mod.AccountId() }
    for id in pairs(Store().accounts) do if id ~= ids[1] then ids[#ids + 1] = id end end
    table.sort(ids, function(a, b)
        if a == mod.AccountId() then return true elseif b == mod.AccountId() then return false end
        return mod.AccountLabel(a) < mod.AccountLabel(b)
    end)
    return ids
end

function mod.AccountLabel(id)
    if id == mod.AccountId() then return "This account" end
    local a = Store().accounts[id]
    return "Account of " .. ((a and a.owner) and MMT.ShownName(a.owner) or "?")
end

-- accounts of a scope: TEAM | ACCOUNT | ALL | acc:<id>
function mod.ScopeAccounts(scope)
    if scope == "ACCOUNT" then return { mod.AccountId() } end
    if scope == "ALL" then return mod.AccountIds() end
    local id = scope and scope:match("^acc:(.+)$")
    if id then return mod.Account(id) and { id } or {} end
    local seen, list = {}, {}
    local members = MMT.SortedMembers()
    local me = MMT.PlayerFull()
    if me then table.insert(members, 1, me) end
    for _, key in ipairs(members) do
        local acc = mod.AccountOf(key)
        if acc and not seen[acc] and mod.Account(acc) then seen[acc] = true; list[#list + 1] = acc end
    end
    return list
end

function mod.ScopeChoices()
    local l = {
        { value = "TEAM", text = "Current team" },
        { value = "ACCOUNT", text = "Current account" },
    }
    for _, id in ipairs(mod.AccountIds()) do
        if id ~= mod.AccountId() then l[#l + 1] = { value = "acc:" .. id, text = mod.AccountLabel(id) } end
    end
    l[#l + 1] = { value = "ALL", text = "All accounts" }
    return l
end

-- combined gold of the scope per chart day: { {date, copper|nil}, ... }
function mod.GoldSeries(scope)
    local list = mod.Days()
    local total, any = {}, {}
    for _, id in ipairs(mod.ScopeAccounts(scope)) do
        local a = mod.Account(id)
        local series = Carry(a and a.days, list)
        for i = 1, #list do
            if series[i] then total[i] = (total[i] or 0) + series[i]; any[i] = true end
        end
    end
    local out = {}
    for i, d in ipairs(list) do out[i] = { d, any[i] and total[i] or nil } end
    return out
end

---------------------------------------------------------------------------
-- Names (privacy): team members by the privacy setting, other characters of
-- an account by the same rule ("Class X" / "Slot X" become "Druid (alt)")
---------------------------------------------------------------------------
function mod.CharName(key, class)
    if MMT.db.team[key] or MMT.IsSelf(key) then return MMT.ShownName(key) end
    local mode = MMT.db.privacy and MMT.db.privacy.nameMode or "FIRST"
    if mode == "CLASS" or mode == "SLOT" then
        local label = class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or "Character"
        return label .. " (alt)"
    end
    return MMT.NameFor(key, mode)
end

function mod.Money(copper)
    if not copper then return "-" end
    copper = math.floor(copper)
    local style = M.db.money
    if style == "COINS" then
        -- this client has C_CurrencyInfo's; the old global may be missing
        local coins = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
        if coins then
            local ok, text = pcall(coins, copper)
            if ok and type(text) == "string" then return text end
        end
    end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if style == "GOLD" then return ("%dg"):format(g) end
    return ("%dg %ds %dc"):format(g, s, c)
end

---------------------------------------------------------------------------
-- Team: send and receive account summaries
---------------------------------------------------------------------------
function mod.SendSummary()
    if not (M.enabled and M.db.share) then return end
    local a = mod.OwnAccount()
    local summary = {
        id = a.id, chars = a.chars, days = a.days,
        kills = Top(a.kills, 25), deaths = Top(a.deaths, 10),
    }
    MMT.SendLong("STA:" .. MMT.Pack(MMT.Serialize(summary)))
end

-- Sending is never real time: a change (gold, a kill, a death) only marks
-- the summary as changed. It goes out
--   * never in combat: the next check after combat ends,
--   * at most once every "sendEvery" minutes (setting, default 5),
--   * as a large transfer (lowest priority), so it never delays alerts.
-- An answer to a request (STQ) may come sooner, but at most every 20 s.
local dirty, wanted = false, false   -- changed / someone asked for it
local lastSent = -math.huge
local timer
local ANSWER_GAP = 20

local function InCombat()
    return (InCombatLockdown and InCombatLockdown()) or MMT.Safe(UnitAffectingCombat, "player") or false
end

local Check
local timerAt = 0
local function Schedule(delay)
    delay = math.max(1, delay)
    if timer then
        if timerAt <= GetTime() + delay then return end   -- an earlier check is already planned
        timer:Cancel()
    end
    timerAt = GetTime() + delay
    timer = C_Timer.NewTimer(delay, function() timer = nil Check() end)
end

Check = function()
    if not (M.enabled and M.db.share) or not (dirty or wanted) then return end
    if InCombat() then return end   -- PLAYER_REGEN_ENABLED checks again
    local gap = wanted and ANSWER_GAP or (M.db.sendEvery or 5) * 60
    local wait = lastSent + gap - GetTime()
    if wait > 0 then Schedule(wait) return end
    dirty, wanted = false, false
    lastSent = GetTime()
    mod.SendSummary()
end

-- something changed (answer = a team member asked for it)
function mod.SendSoon(answer)
    if answer == true then wanted = true else dirty = true end
    Schedule(answer == true and 2 or 5)
end

M:On("PLAYER_REGEN_ENABLED", function() C_Timer.After(3, Check) end)

-- the next summary as soon as allowed (login, sharing switched on)
function mod.SendNow()
    wanted = true
    lastSent = -math.huge
    Check()
end

-- "Request update" button: every team member sends its summary (out of
-- combat, within 20 s), and this account's goes out too
local lastRequest = 0
function mod.RequestUpdate()
    if not (M.enabled and M.db.share) then
        MMT.Print("Statistics: sharing with the team is switched off (Settings tab).")
        return
    end
    if GetTime() - lastRequest < 10 then return end
    lastRequest = GetTime()
    MMT.SendToTeam("STQ", true, "NORMAL")
    mod.SendNow()
    MMT.Print("Statistics: asked the team for their gold and kill statistics.")
end

-- joining a group: exchange summaries 20 s later
M:On("GROUP_JOINED", function()
    C_Timer.After(20, function()
        if not (M.enabled and M.db.share) or not IsInGroup() then return end
        MMT.SendToTeam("STQ", true, "NORMAL")
        mod.SendNow()
    end)
end)

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if not M.db.share then return end
    if text == "STQ" then mod.SendSoon(true) return end
    local body = text:match("^STA:(.*)$")
    if not body then return end
    local plain = MMT.Unpack(body)
    local t = plain and MMT.Deserialize(plain)
    if type(t) ~= "table" or type(t.id) ~= "string" then
        M:Debug("STA from %s could not be read", MMT.Repr(key))
        return
    end
    local s = Store()
    s.memberAccount[key] = t.id
    if t.id == s.accountId then return end   -- a character of this account on another client
    s.accounts[t.id] = {
        id = t.id, owner = key, at = time(),
        chars = type(t.chars) == "table" and t.chars or {},
        days = type(t.days) == "table" and t.days or {},
        kills = type(t.kills) == "table" and t.kills or {},
        deaths = type(t.deaths) == "table" and t.deaths or {},
    }
    if mod.Redraw then mod.Redraw() end
end)

-- gold
M:On("PLAYER_MONEY", function() mod.RecordGold() mod.SendSoon() if mod.Redraw then mod.Redraw() end end)
-- Right after login the money may not be known yet: recorded a moment later.
-- Not at logout: the client already reports 0 then (every change before is
-- recorded by PLAYER_MONEY anyway).
M:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, mod.RecordGold) end)

M.OnEnable = function()
    Store()
    C_Timer.After(3, mod.RecordGold)
    C_Timer.After(8, function()
        if not (M.enabled and M.db.share) then return end
        mod.SendNow()   -- waits for the end of combat if needed
        MMT.SendToTeam("STQ", true, "NORMAL")
    end)
end

-- the team's accounts again (Gold / Kills tab opened, data older than 10 min)
function mod.RequestIfOld()
    if not (M.enabled and M.db.share) then return end
    local newest = 0
    for _, a in pairs(Store().accounts) do newest = math.max(newest, a.at or 0) end
    if time() - newest > 600 then MMT.SendToTeam("STQ", true, "NORMAL") end
end

M.Report = function(_, add)
    local s = Store()
    local nChars, nAcc = 0, 0
    for _ in pairs(s.chars) do nChars = nChars + 1 end
    for _ in pairs(s.accounts) do nAcc = nAcc + 1 end
    add(("-- Statistics 1.0.8  account=%s characters=%d otherAccounts=%d gold=%s kills=%s share=%s"):format(
        s.accountId, nChars, nAcc, tostring(M.db.trackGold), tostring(M.db.trackKills), tostring(M.db.share)))
    for key, c in pairs(s.chars) do
        local n = 0
        for _ in pairs(c.days or {}) do n = n + 1 end
        add(("  char %s: gold=%s days=%d kills=%d deaths=%d"):format(MMT.Repr(key), tostring(c.gold), n,
            c.killTotal or 0, c.deathTotal or 0))
    end
    for id, a in pairs(s.accounts) do
        add(("  account %s from %s, %d s ago"):format(id, MMT.Repr(a.owner), time() - (a.at or 0)))
    end
    if mod.KillReport then mod.KillReport(add) end
end
