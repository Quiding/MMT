-- MMT Statistics: profession skill-ups of this account's characters.
--
-- Per character record (Module.lua Store().chars[key].prof), kept on this
-- account only (never sent to the team):
--   cur  = { [profession] = { r = rank, m = max rank, k = "P" primary | "S" secondary } }
--          what the character knows now (unlearned professions drop out here)
--   hist = { { h = hour (unix time, whole hours), lv = character level, p = profession,
--              s = rank before, e = rank after, n = skill-ups,
--              g1 = gold (copper) at the first, g2 = at the last skill-up }, ... }
--          oldest first; skill-ups of one profession in the same hour on the same
--          character level are one entry. Kept when a profession is unlearned.
--   seen = true once the professions were read the first time (that read only
--          sets the starting point, nothing is counted)
-- The levels (Leveling.lua levels[L].pr) and instance runs (runs[i].pr) also get
-- { [profession] = { s, e } } for the Leveling and Zones tabs.

local _, mod = ...
local MMT = MMT
local M = mod.M

local Safe, IsSecret = MMT.Safe, MMT.IsSecret
local MAX_HIST = 3000

-- skill line IDs -> English names (the names the records use)
local LINES = {
    [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering",
    [182] = "Herbalism", [165] = "Leatherworking", [186] = "Mining", [393] = "Skinning",
    [197] = "Tailoring", [755] = "Jewelcrafting", [773] = "Inscription",
    [185] = "Cooking", [356] = "Fishing", [129] = "First Aid",
}
mod.PRIMARY_PROFESSIONS = {
    Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Herbalism = true,
    Leatherworking = true, Mining = true, Skinning = true, Tailoring = true, Jewelcrafting = true, Inscription = true,
}
mod.SECONDARY_PROFESSIONS = { "Cooking", "Fishing", "First Aid" }
local SECONDARY = { Cooking = true, Fishing = true, ["First Aid"] = true }

local function Plain(v) if v == nil or IsSecret(v) then return nil end return v end

-- what this character knows now: { [name] = { r, m, k } }
function mod.ReadProfessions()
    local out = {}
    local function Add(name, rank, max)
        name, rank, max = Plain(name), tonumber(Plain(rank)), tonumber(Plain(max))
        if type(name) ~= "string" or not rank then return end
        local kind = mod.PRIMARY_PROFESSIONS[name] and "P" or (SECONDARY[name] and "S") or nil
        if kind and not out[name] then out[name] = { r = rank, m = max, k = kind } end
    end
    if GetProfessions and GetProfessionInfo then
        local list = { Safe(GetProfessions) }
        for i = 1, 6 do
            local index = list[i]
            if index and not IsSecret(index) then
                local ok, name, _, rank, max, _, _, line = pcall(GetProfessionInfo, index)
                if ok then Add(LINES[line] or name, rank, max) end
            end
        end
    end
    -- the skill list (classic API): First Aid and anything GetProfessions leaves out
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, (tonumber(Plain(Safe(GetNumSkillLines))) or 0) do
            local ok, name, header, _, rank, _, _, max = pcall(GetSkillLineInfo, i)
            if ok and not header then Add(name, rank, max) end
        end
    end
    return out
end

local function Hour(t) return math.floor(t / 3600) * 3600 end

-- a skill-up of one profession from `from` to `to`
local function Record(c, name, from, to)
    c.prof.hist = c.prof.hist or {}
    local hist = c.prof.hist
    local now = time()
    local h, L = Hour(now), mod.LevelNow and mod.LevelNow() or 0
    local money = tonumber(Plain(Safe(GetMoney)))
    local last
    for i = #hist, math.max(1, #hist - 20), -1 do
        local e = hist[i]
        if e.h == h and e.p == name and e.lv == L then last = e break end
        if e.h < h then break end
    end
    if last then
        last.e = math.max(last.e or to, to)
        last.n = (last.n or 0) + (to - from)
        last.g2 = money or last.g2
    else
        hist[#hist + 1] = { h = h, lv = L, p = name, s = from, e = to, n = to - from, g1 = money, g2 = money }
        while #hist > MAX_HIST do table.remove(hist, 1) end
    end
    if mod.OnProfessionUp then mod.OnProfessionUp(name, from, to) end
    M:Debug("profession: %s %d -> %d (level %d)", name, from, to, L)
end

function mod.CheckProfessions()
    if not M.enabled or M.db.trackProfessions == false then return end
    local c = mod.Char()
    if not c then return end
    c.prof = c.prof or {}
    local now = mod.ReadProfessions()
    local cur = c.prof.cur or {}
    -- nothing readable (right after login the lists can be empty): keep what is known
    if next(now) == nil and next(cur) ~= nil then return end
    if c.prof.seen then
        for name, p in pairs(now) do
            local old = cur[name]
            if old and p.r > (old.r or 0) then Record(c, name, old.r or 0, p.r) end
        end
        for name in pairs(cur) do
            if not now[name] then M:Debug("profession: %s unlearned (history kept)", name) end
        end
    end
    c.prof.cur = now
    c.prof.seen = true
    if mod.Redraw then mod.Redraw() end
end

local soon
local function CheckSoon()
    if soon then return end
    soon = true
    C_Timer.After(0.5, function() soon = nil mod.CheckProfessions() end)
end
for _, e in ipairs({ "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "TRADE_SKILL_LIST_UPDATE", "LEARNED_SPELL_IN_TAB" }) do
    M:On(e, CheckSoon)
end
M:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, mod.CheckProfessions) end)

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------
-- the five tiles of one character: primary 1, primary 2, Cooking, Fishing, First Aid
-- -> { { label, name or nil, r, m }, ... }
function mod.ProfessionTiles(c)
    local cur = c and c.prof and c.prof.cur or {}
    local prim = {}
    for name, p in pairs(cur) do if p.k == "P" then prim[#prim + 1] = name end end
    table.sort(prim)
    local tiles = {}
    for i = 1, 2 do
        local name = prim[i]
        tiles[#tiles + 1] = { "Primary " .. i, name, name and cur[name].r, name and cur[name].m }
    end
    for _, name in ipairs(mod.SECONDARY_PROFESSIONS) do
        local p = cur[name]
        tiles[#tiles + 1] = { "Secondary", p and name or nil, p and p.r, p and p.m, fixed = name }
    end
    return tiles
end

-- history rows of a scope ("CHAR" | "ACCOUNT" | "char:<key>") and profession
-- ("ALL" | name), newest first: { key, class, e = entry }
function mod.ProfessionRows(scope, prof)
    local rows = {}
    for key, c in pairs(mod.Store().chars) do
        if mod.InScope(scope, key) then
            for _, e in ipairs(c.prof and c.prof.hist or {}) do
                if prof == "ALL" or prof == nil or e.p == prof then
                    rows[#rows + 1] = { key = key, class = c.class, e = e }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.e.h ~= b.e.h then return a.e.h > b.e.h end
        if a.key ~= b.key then return a.key < b.key end
        return (a.e.p or "") < (b.e.p or "")
    end)
    return rows
end

-- dropdown: All Professions + every profession known or recorded in the scope
function mod.ProfessionChoices(scope)
    local seen, names = {}, {}
    for key, c in pairs(mod.Store().chars) do
        if mod.InScope(scope, key) and c.prof then
            for name in pairs(c.prof.cur or {}) do if not seen[name] then seen[name] = true names[#names + 1] = name end end
            for _, e in ipairs(c.prof.hist or {}) do
                if not seen[e.p] then seen[e.p] = true names[#names + 1] = e.p end
            end
        end
    end
    table.sort(names)
    local l = { { value = "ALL", text = "All Professions" } }
    for _, n in ipairs(names) do l[#l + 1] = { value = n, text = n } end
    return l
end

-- { [profession] = { s, e } } -> total skill-ups, sorted list for tooltips
function mod.ProfessionSum(pr)
    local total, list = 0, {}
    for name, x in pairs(pr or {}) do
        local n = (x.e or 0) - (x.s or 0)
        if n > 0 then
            total = total + n
            list[#list + 1] = { name, x.s, x.e }
        end
    end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    return total, list
end

-- tooltip: Profession | Start | End
function mod.ProfessionTooltip(t, list)
    if #list == 0 then return end
    t:AddLine(" ")
    t:AddDoubleLine("Profession", "Start - End", 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
    for _, x in ipairs(list) do
        t:AddDoubleLine(x[1], ("%d - %d"):format(x[2] or 0, x[3] or 0), 1, 1, 1, 1, 1, 1)
    end
end
