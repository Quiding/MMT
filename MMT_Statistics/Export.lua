-- MMT Statistics: CSV export (Settings tab > Export). Addons can't write
-- files, so the text goes into a box to copy (Ctrl+A, Ctrl+C) and paste into
-- a spreadsheet or a .csv file.
--   mod.ExportCSV(kind, scope, sep) -> text, rows
--   kind  GOLD_CHAR  gold per day and character (this account: other accounts
--                    only send their daily totals)
--         GOLD_ACC   gold per day and account
--         CHARS      one row per character: class, gold, kills, deaths, last seen
--         KILLS      NPCs killed and killed by (this account per character,
--                    other accounts: their top 25 kills / top 10 killers)
--   scope TEAM | ACCOUNT | ALL | acc:<id> (as the tables)
--   sep   "," (decimal point) | ";" (decimal comma, e.g. German Excel)
-- Names follow the privacy setting, like everything MMT shows.

local _, mod = ...
local MMT = MMT
local M = mod.M

mod.EXPORT_KINDS = {
    { value = "GOLD_CHAR", text = "Gold per day and character" },
    { value = "GOLD_ACC", text = "Gold per day and account" },
    { value = "CHARS", text = "Characters" },
    { value = "KILLS", text = "Kills and deaths" },
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
                    c.g and math.floor(c.g) or "", c.k or 0, c.d or 0, c.s and date("%Y-%m-%d %H:%M", c.s) or "")
            end
        end
    elseif kind == "KILLS" then
        Row("Account", "Character", "Type", "NPC", "Count")
        for _, id in ipairs(ids) do
            local label = mod.AccountLabel(id)
            if id == own then
                for _, e in ipairs(Sorted(s.chars)) do
                    local key, c = e[1], e[2]
                    local name = mod.CharName(key, c.class)
                    for _, k in ipairs(Sorted(c.kills, true)) do Row(label, name, "Killed", k[1], k[2]) end
                    for _, k in ipairs(Sorted(c.deaths, true)) do Row(label, name, "Killed by", k[1], k[2]) end
                end
            else
                local a = mod.Account(id)
                for _, k in ipairs(Sorted(a and a.kills, true)) do Row(label, "(top 25 of the account)", "Killed", k[1], k[2]) end
                for _, k in ipairs(Sorted(a and a.deaths, true)) do Row(label, "(top 10 of the account)", "Killed by", k[1], k[2]) end
            end
        end
    end
    return table.concat(lines, "\n"), #lines - 1
end
