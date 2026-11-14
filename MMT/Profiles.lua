-- MMT: saved variables, profiles, export/import and conversion of older
-- saved data (MMT 0.1.x, MMT 2.0.0 test build, OMT).
--
-- MMTDB is account-wide. Every character picks a profile (default
-- "Default"), so all characters of an account share settings by default.
-- Profiles reach other accounts by export/import; /mmt sync sends the core
-- settings of the active profile (Sync.lua).

local _, ns = ...

ns.defaults = {
    -- Team & roles ---------------------------------------------------------
    team  = {},   -- [key "First-Last"] = { name, last, class, order, roles = {[role]=true} }
    roles = {},   -- [role name] = { rules = { rule, ... } }
    trade = { enabled = true, shareRoles = {} },   -- shareRoles: [role] = true, shared evenly among its members

    -- Info window ------------------------------------------------------------
    xp = {
        enabled     = true,
        locked      = false,
        showSelf    = true,
        showLevel   = true,
        clickThrough = false,    -- mouse passes through (no mouseover details)
        showRested  = true,
        layerHopNotify = true,   -- pulsing "Layer Hop" when a layer/phase switch is offered
        layerHopAuto   = false,  -- accept it automatically ...
        layerHopDelay  = 5,      -- ... after this many seconds
        followCheck    = true,   -- watch whether team characters keep following
        followWarn     = true,   -- raid warning "<Name> stopped following"
        followSound    = true,   -- raid warning sound
        followIgnoreCombat = true, -- breaks in combat only count if still not following after combat
        followIgnoreInstance = false, -- breaks inside a dungeon / raid never count
        followCombatDelay  = 5,    -- ... this many seconds after combat
        showBars    = true,
        restedColour = { r = 0.65, g = 0.45, b = 1.0 },   -- rested XP on the bar (cogwheel of the piece "Rested XP")
        restedAlpha  = 0.30,
        barColour   = { r = 0.31, g = 0.70, b = 1.00 },   -- XP fill without class colours (cogwheel of "Bar value")
        valueDecimals = 1,       -- decimals of the XP % (cogwheel of "Bar value")
        levelPrefix = true,      -- "L60" or "60" (cogwheel of "Level")
        bagWarn     = 4,         -- free bag slots: yellow at or below (cogwheel of "Free bag slots")
        bagBad      = 0,         -- ... red at or below
        durWarn     = 60,        -- durability %: yellow below (cogwheel of "Durability")
        durBad      = 25,        -- ... red below
        layerMark   = false,     -- layer shown in orange when not yours (cogwheel of "Layer")
        levelUpHint = true,      -- pulsing "LvlUp available" when the ready quests reach the next level (LevelUp.lua)
        flightHint  = true,      -- "Fly to X, mm:ss" / "arrived X" in place of the XP (Flight.lua)
        xpFlash     = true,      -- big XP gains (3 % of the level or more) light up the bar and the XP value
        classColors = true,
        showGold    = true,
        goldFormat  = "GOLD",    -- GOLD: 1234g | FULL: gold, silver, copper
        showBags    = true,      -- free bag slots
        showDurability = true,
        durability  = "LOWEST",  -- LOWEST: item with the least durability | AVERAGE: all items
        font        = "Friz Quadrata",
        size        = 12,
        outline     = "OUTLINE",
        align       = "SPLIT",   -- SPLIT (name left, values right) | LEFT | CENTER | RIGHT
        pieceAlign  = "CENTER",  -- pieces lined up in columns, inside them LEFT | CENTER | RIGHT | ICONS (by the
                                 -- piece's icon: gold right, bags / durability left); OFF: each row flows
        width       = 325,
        barMode     = "XP",      -- XP | REP: what the bar (and its % value) shows
        barHeight   = 18,
        rowGap      = 3,         -- pixels between the rows
        bgAlpha     = 0.35,
        alpha       = 1,
        scale       = 1,
        point       = { "LEFT", "LEFT", 300, 0 },   -- vertically centred, 300 from the left edge (grows up and down)
    },

    -- FTL: macros with {FTL} = the character you are playing (FTL.lua)
    ftl = {
        enabled    = true,
        detect     = "MANUAL",  -- MANUAL: click, key, command | MOVE: moving a character on its own makes it the leader
        nameFormat = "FULL",    -- FULL "First Last" | FIRST "First" | UNIT party/raid unit ("party2")
        skipSelf   = true,      -- leave {FTL} lines out on the leader's own client
        crown      = true,      -- crown in front of the leader in the Info window
        crownSide  = "LEFT",    -- LEFT of the name | RIGHT of it
        announce   = true,      -- chat line when the leader changes
        macros = {
            { name = "FTL Follow", body = "/follow {FTL}\n/focus {FTL}" },
            { name = "FTL Assist", body = "/assist {FTL}\n/focus {FTL}" },
            -- examples for ability macros (names: at most 16 characters)
            { name = "Pri: Lesser Heal", body = "/cast [@{FTL},nodead] Lesser Heal", since = 1 },
            { name = "Dru: Heal Touch", body = "/cast [@{FTL},nodead] Healing Touch", since = 1 },
            { name = "Sha: Light Bolt", body = "/cast [@focustarget,nodead,harm] Lightning Bolt", since = 3 },
        },
    },

    -- flight paths with the team (Taxi.lua)
    taxi = {
        enabled = true,   -- take the flight path a team member picks (flight map open here)
        report  = true,   -- chat line when following a flight
        tellLeader = true, -- the leader's chat says who followed (or couldn't)
        delay   = 1,      -- seconds (1-5) before following, so the flight maps can open
        train   = false,  -- Flight-Train: one by one, "delay" seconds apart, in team order
    },

    -- privacy (Privacy.lua): how characters are shown
    privacy = {
        nameMode    = "FIRST",   -- FIRST | LAST | FULL | CLASS ("Druid 1") | SLOT ("Slot 1"); everywhere in MMT
        debugFull   = true,      -- keep full names in debug logs and reports
        hideOutside = false,     -- also replace names in Blizzard frames, chat and tooltips
        worldNames  = "NAMEPLATES", -- with hideOutside, the game's names above characters:
                                 -- NAMEPLATES (friendly nameplates on, own name off) | HIDE (friendly player names off)
    },

    -- room warnings (Warnings.lua): shown on the leader's client
    warn = {
        bags        = true,   -- bags almost full
        bagsAt      = 2,      -- ... at this many free slots or fewer
        quests      = true,   -- quest log almost full
        questsAt    = 3,      -- ... at this many free quest slots or fewer
        raidWarning = true,
        sound       = false,
    },

    -- crowd control check (CC.lua)
    cc = {
        enabled     = true,   -- report when a team character can't move
        warn        = true,   -- raid warning "<Name> is stunned" (on the FTL leader's client)
        sound       = true,   -- raid warning sound
        stun        = true,   -- stuns
        fear        = true,   -- fears, charms, mind control
        incap       = true,   -- incapacitates: polymorph, sap, sleep ...
        root        = true,   -- roots
        minDuration = 2,      -- ignore effects shorter than this many seconds
    },

    -- team communication
    comm = {
        guild = false,   -- send team messages on the guild channel (all characters in one guild)
        fast  = false,   -- 1200 instead of 800 bytes per second
    },

    -- settings of modules: [moduleName] = { ... } (defaults come from the module)
    modules = {},

    -- Automations ----------------------------------------------------------
    shiftBypass = true,
    -- quest settings moved to the Quest Tracker module (profile.quests of older
    -- profiles is copied over by the module once)
    gossip   = { vendor = true, taxi = true, bank = true, dialog = true },
    -- items never traded / mailed by MMT, whatever role wants them:
    -- { { itemID, name, trade = true, mail = true }, ... } (Trade / Mail / Vendor > Exclusion List)
    exclusions = {},
    merchant = { sellGrey = true, repair = true, guildRepair = false, report = true, tellLeader = true, moneyFormat = "text",
                 sellRole = "", neverRole = "",          -- sell list / never-sell list (role names)
                 buy = false, buyList = {} },            -- buy list: { itemID, name, count, chars = { teamKey, ... } or nil = every character }
    mail     = { enabled = true, goldTo = "", keepGold = 100 },     -- mailbox button: role items to the team, gold above keepGold
    gbank    = { enabled = true, role = "", tab = 1, gold = false, keepGold = 100 },   -- guild bank button
    -- automations
    mount    = { mount = true, dismount = true, chosen = 0 },   -- with the leader; chosen: the "Mount team: chosen mount" key (0 = random favourite)
    death    = { release = true, revive = true,                 -- team buttons under the death / corpse dialogs
                 acceptRes = { team = true, friends = false, guild = false, anyone = false },
                 acceptSummon = { team = true, friends = false, guild = false, anyone = false } },
    invites  = { friends = true, bnet = true, guild = true, team = true, whisper = true, keyword = "mybox" },
    camera   = { enabled = true, factor = 2.6 },
    distance = {
        enabled = true, locked = false, hideNoTarget = false, colorize = false,
        font = "Friz Quadrata", size = 14, outline = "OUTLINE", align = "CENTER",
        bgAlpha = 0.25, width = 90, point = { "CENTER", "CENTER", 0, -160 },
    },
}

local DEFAULT = "Default"

---------------------------------------------------------------------------
-- Table helpers
---------------------------------------------------------------------------
local function Copy(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, v in pairs(src) do t[k] = Copy(v) end
    return t
end
ns.CopyTable = Copy

local function IsArray(t) return next(t) == nil or t[1] ~= nil end

-- Fills in missing keys. Arrays (frame points) and the team/role maps are
-- copied whole when missing, never merged element by element.
local function MergeDefaults(dst, src)
    if type(src) ~= "table" then return end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = Copy(v)
            elseif not IsArray(v) then
                MergeDefaults(dst[k], v)
            end
        elseif dst[k] == nil or type(dst[k]) ~= type(v) then
            dst[k] = v
        end
    end
end

---------------------------------------------------------------------------
-- Conversion of older profile layouts (runs on every activation/import;
-- does nothing for profiles that are already current)
---------------------------------------------------------------------------
local function KeyFromName(full)
    local first, last = full:match("^(%S+)%s+(.+)$")
    if first then return first .. "-" .. last:gsub("%s", "-"), first, last end
    first, last = full:match("^([^-]+)-(.+)$")
    if first then return full, first, last end
    return full, full, nil
end

local function ConvertProfile(p)
    -- MMT 2.0.0 test build: team = { "First Last", ... }, roles = { {name, members, grey, boe, items} }
    if type(p.team) == "table" and type(p.team[1]) == "string" then
        local team = {}
        for i, full in ipairs(p.team) do
            local key, first, last = KeyFromName(full)
            team[key] = { name = first, last = last, order = i, roles = {} }
        end
        p.team = team
    end
    if type(p.roles) == "table" and type(p.roles[1]) == "table" and p.roles[1].name then
        local roles = {}
        for _, r in ipairs(p.roles) do
            local rules = {}
            for _, id in ipairs(r.items or {}) do rules[#rules + 1] = { type = "item", itemID = id } end
            if r.grey then rules[#rules + 1] = { type = "quality", quality = 0 } end
            if r.boe then rules[#rules + 1] = { type = "boe" } end
            roles[r.name] = { rules = rules }
            for memberName in pairs(r.members or {}) do
                local key = KeyFromName(memberName)
                if p.team[key] then p.team[key].roles[r.name] = true end
            end
        end
        p.roles = roles
    end

    -- MMT 0.1.x: separate font/window tables, xp.shown, xp.point as string
    if type(p.xp) == "table" then
        local xp = p.xp
        if xp.shown ~= nil then xp.enabled = xp.shown; xp.shown = nil end
        if type(xp.point) == "string" then
            xp.point = { xp.point, xp.point, xp.x or 30, xp.y or -250 }
            xp.x, xp.y = nil, nil
        end
        if type(p.font) == "table" then
            if p.font.path then xp.font = ns.FontNameForPath(p.font.path) end
            if p.font.size then xp.size = p.font.size end
            if p.font.outline then xp.outline = (p.font.outline == "") and "NONE" or p.font.outline end
            p.font = nil
        end
        if type(p.window) == "table" then
            xp.scale = p.window.scale or xp.scale
            xp.alpha = p.window.alpha or xp.alpha
            xp.width = p.window.width or xp.width
            xp.barHeight = p.window.barHeight or xp.barHeight
            p.window = nil
        end
    end

    -- up to 0.4.2 "locked" also meant click-through
    if type(p.xp) == "table" and p.xp.clickThrough == nil and p.xp.locked ~= nil then
        p.xp.clickThrough = p.xp.locked and true or false
    end

    -- 0.1.1 stored the last name in a "realm" field
    for _, m in pairs(p.team or {}) do
        if type(m) == "table" and m.realm then
            m.last = m.last or m.realm
            m.realm = nil
        end
    end

    -- MMT 0.3.0: Item Compare settings lived in the core profile
    if type(p.compare) == "table" then
        p.modules = type(p.modules) == "table" and p.modules or {}
        p.modules.ItemCompare = p.modules.ItemCompare or p.compare
        p.compare = nil
    end

    -- give every member an order (0.1.x sorted alphabetically)
    if type(p.team) == "table" then
        local keys = {}
        for key, m in pairs(p.team) do
            if type(m) == "table" then
                m.roles = m.roles or {}
                if not m.order then keys[#keys + 1] = key end
            end
        end
        table.sort(keys)
        local max = 0
        for _, m in pairs(p.team) do if type(m) == "table" and m.order and m.order > max then max = m.order end end
        for _, key in ipairs(keys) do max = max + 1; p.team[key].order = max end
    end
    -- buy list (MMT 0.9.60): one character ("who") becomes a list of characters ("chars")
    if type(p.merchant) == "table" and type(p.merchant.buyList) == "table" then
        for _, e in ipairs(p.merchant.buyList) do
            if type(e) == "table" and e.who ~= nil then
                if e.who ~= "" and e.chars == nil then e.chars = { e.who } end
                e.who = nil
            end
        end
    end
end
ns.ConvertProfile = ConvertProfile
ns.MergeDefaults = MergeDefaults

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
function ns.ProfileNames()
    local names = {}
    for name in pairs(MMTDB.profiles) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        if a == DEFAULT then return true elseif b == DEFAULT then return false end
        return a:lower() < b:lower()
    end)
    return names
end

function ns.CurrentProfileName() return ns.profileName or DEFAULT end

-- default macros added later (since = n) go once into older profiles:
-- 1 = heal examples (0.9.40), 3 = Sha: Light Bolt (0.9.42). A macro the
-- player deleted afterwards stays deleted. (2 was "FTL Focus", 0.9.41-0.9.42.)
-- 0.9.42 also: Follow and Assist set the focus too, and "Pal: Holy Light" is
-- gone; both only where the player left the macro as MMT made it.
local OLD_DEFAULTS = {
    ["FTL Follow"] = { "/follow {FTL}", "/follow {FTL}\n/focus {FTL}" },
    ["FTL Assist"] = { "/assist {FTL}", "/assist {FTL}\n/focus {FTL}" },
    ["Pal: Holy Light"] = { "/cast [@{FTL},nodead] Holy Light", false },
}
-- 0.9.43: the standalone "FTL Focus" is gone (Follow and Assist set the focus)
local OLD_DEFAULTS_4 = { ["FTL Focus"] = { "/focus {FTL}", false } }
local function AddMacroExamples(p)
    local ftl = p.ftl
    if type(ftl) ~= "table" or type(ftl.macros) ~= "table" then return end
    local done = tonumber(ftl.examples) or 0
    local function Change(list)
        for i = #ftl.macros, 1, -1 do
            local m = ftl.macros[i]
            local change = m.name and list[m.name]
            if change and ns.Trim(m.body or "") == change[1] then
                if change[2] then m.body = change[2] else table.remove(ftl.macros, i) end
            end
        end
    end
    if done < 3 then Change(OLD_DEFAULTS) end
    if done < 4 then Change(OLD_DEFAULTS_4) end
    local have, newest = {}, done
    for _, m in ipairs(ftl.macros) do if m.name then have[m.name] = true end end
    for _, m in ipairs(ns.defaults.ftl.macros) do
        if m.since and m.since > done then
            if not have[m.name] then ftl.macros[#ftl.macros + 1] = { name = m.name, body = m.body } end
            newest = math.max(newest, m.since)
        end
    end
    ftl.examples = math.max(newest, 4)
end

-- example roles, once per profile (new and older ones); deleted ones stay deleted
-- (since: the example set that brought it; p.roleExamples = the newest one added)
local EXAMPLE_ROLES = {
    { name = "Tailor", since = 1, rules = { { type = "group", group = "cloth" } } },
    { name = "Enchanter", since = 1, rules = { { type = "boe" }, { type = "group", group = "enchanting" } } },
    { name = "Tanner / Leather", since = 2, rules = { { type = "group", group = "leather" } } },
    { name = "Smith", since = 2, rules = { { type = "group", group = "metal" } } },
    { name = "Herbalist", since = 2, rules = { { type = "group", group = "herbs" } } },
}
local ROLE_EXAMPLES = 2
local function AddRoleExamples(p)
    if type(p.roles) ~= "table" then return end
    local done = tonumber(p.roleExamples) or 0
    if done >= ROLE_EXAMPLES then return end
    p.roleExamples = ROLE_EXAMPLES
    for _, r in ipairs(EXAMPLE_ROLES) do
        if r.since > done and not p.roles[r.name] then p.roles[r.name] = { rules = Copy(r.rules) } end
    end
end

local function Activate(name)
    if not MMTDB.profiles[name] then name = DEFAULT end
    local p = MMTDB.profiles[name]
    ConvertProfile(p)
    MergeDefaults(p, ns.defaults)
    AddMacroExamples(p)
    AddRoleExamples(p)
    ns.db = p
    ns.profileName = name
    ns.Fire("PROFILE_CHANGED")
end

local function CharKey() return ns.PlayerFull() or "?" end

function ns.SetProfile(name)
    if not MMTDB.profiles[name] then return false end
    MMTDB.profileKeys[CharKey()] = name
    Activate(name)
    ns.Refresh()
    return true
end

-- source = table to copy, or nil for an empty profile
function ns.CreateProfile(name, source)
    name = ns.Trim(name)
    if name == "" or MMTDB.profiles[name] then return false end
    MMTDB.profiles[name] = source and Copy(source) or {}
    return true
end

function ns.CopyProfileInto(sourceName)
    local src = MMTDB.profiles[sourceName]
    if not src or sourceName == ns.profileName then return false end
    MMTDB.profiles[ns.profileName] = Copy(src)
    Activate(ns.profileName)
    ns.Refresh()
    return true
end

function ns.ResetProfile()
    MMTDB.profiles[ns.profileName] = {}
    Activate(ns.profileName)
    ns.Refresh()
end

function ns.DeleteProfile(name)
    if name == DEFAULT or not MMTDB.profiles[name] then return false end
    MMTDB.profiles[name] = nil
    for char, p in pairs(MMTDB.profileKeys) do
        if p == name then MMTDB.profileKeys[char] = DEFAULT end
    end
    if ns.profileName == name then Activate(DEFAULT) ns.Refresh() end
    return true
end

---------------------------------------------------------------------------
-- Serializer (plain text, length-prefixed; nothing is ever executed)
-- Same format as MMT 0.1.x, so old export strings still import.
---------------------------------------------------------------------------
local function ser(v, out, depth)
    if depth > 20 then return end
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "number" then
        out[#out + 1] = "n" .. tostring(v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do
            local kt, xt = type(k), type(x)
            if (kt == "string" or kt == "number")
                and (xt == "string" or xt == "number" or xt == "boolean" or xt == "table") then
                ser(k, out, depth + 1)
                ser(x, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    end
end

function ns.Serialize(v)
    local out = {}
    ser(v, out, 0)
    return table.concat(out)
end

local function deser(s, i, depth)
    if depth > 20 then error("too deep") end
    local c = s:sub(i, i)
    if c == "s" then
        local len, e = s:match("^(%d+):()", i + 1)
        if not len then error("bad string") end
        len = tonumber(len)
        local str = s:sub(e, e + len - 1)
        if #str ~= len then error("truncated") end
        return str, e + len
    elseif c == "n" then
        local num, e = s:match("^([^;]*);()", i + 1)
        local n = num and tonumber(num)
        if not n then error("bad number") end
        return n, e
    elseif c == "T" then
        return true, i + 1
    elseif c == "F" then
        return false, i + 1
    elseif c == "{" then
        local t = {}
        i = i + 1
        while s:sub(i, i) ~= "}" do
            if i > #s then error("unterminated") end
            local k, v
            k, i = deser(s, i, depth + 1)
            if type(k) ~= "string" and type(k) ~= "number" then error("bad key") end
            v, i = deser(s, i, depth + 1)
            t[k] = v
        end
        return t, i + 1
    end
    error("bad token")
end

function ns.Deserialize(s)
    s = ns.Trim(s)
    local ok, v, pos = pcall(deser, s, 1, 0)
    if ok and pos == #s + 1 then return v end
    return nil
end

-- anonymous: every team member becomes their class and a number (Paladin1, Paladin2,
-- Mage1, ... in team order) everywhere in the export - see ns.AnonymousProfile
function ns.ExportProfile(anonymous)
    if anonymous then
        local data, name = ns.AnonymousProfile(ns.db, ns.CurrentProfileName())
        return "MMT1:" .. ns.Serialize({ name = name, data = data })
    end
    return "MMT1:" .. ns.Serialize({ name = ns.CurrentProfileName(), data = ns.db })
end

-- Without names: a renamed deep copy of a profile's data (and the profile name), each
-- member's key ("First-Last") replaced by Class + number wherever it stands as a whole
-- name - table keys and texts, "CHAR:First-Last" in module settings too. A first name
-- alone only where a key or text is exactly that name (inside a longer text it could be
-- a word), and only when no other member has the same first name.
local function ClassWord(class)
    local loc = class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
    local w = type(loc) == "string" and loc or (type(class) == "string" and class ~= "" and (class:sub(1, 1) .. class:sub(2):lower())) or "Member"
    return (w:gsub("[^%w]", ""))
end

-- a byte that belongs to a name (letters, digits, - and ', any non-ASCII byte)
local function IsNameChar(c)
    return c ~= "" and (c:find("^[%w%-']") ~= nil or c:byte() >= 128)
end

local function ReplaceWord(s, word, repl)
    if not s:find(word, 1, true) then return s end
    local out, i = {}, 1
    while true do
        local a, b = s:find(word, i, true)
        if not a then break end
        if not IsNameChar(s:sub(a - 1, a - 1)) and not IsNameChar(s:sub(b + 1, b + 1)) then
            out[#out + 1] = s:sub(i, a - 1)
            out[#out + 1] = repl
        else
            out[#out + 1] = s:sub(i, b)
        end
        i = b + 1
    end
    out[#out + 1] = s:sub(i)
    return table.concat(out)
end

function ns.AnonymousProfile(data, profileName)
    local members = {}
    for key, m in pairs(type(data) == "table" and type(data.team) == "table" and data.team or {}) do
        if type(key) == "string" and type(m) == "table" then
            members[#members + 1] = { key = key, first = type(m.name) == "string" and m.name or nil, class = m.class, order = tonumber(m.order) or 999 }
        end
    end
    table.sort(members, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.key < b.key end)
    local count, firsts = {}, {}
    for _, m in ipairs(members) do if m.first then firsts[m.first] = (firsts[m.first] or 0) + 1 end end
    -- placeholders go in through tokens, so a new name is never matched again
    local reps, final, exact, newOf = {}, {}, {}, {}
    for i, m in ipairs(members) do
        local w = ClassWord(m.class)
        count[w] = (count[w] or 0) + 1
        local new = w .. count[w]
        local tok = "\001" .. i .. "\001"
        final[tok] = new
        reps[#reps + 1] = { old = m.key, tok = tok }
        newOf[m.key] = new
        if m.first and m.first ~= m.key and firsts[m.first] == 1 then exact[m.first] = new end
    end
    table.sort(reps, function(a, b) return #a.old > #b.old end)   -- "Anna-Smith" before "Anna"
    local function Str(s)
        if exact[s] then return exact[s] end
        for _, r in ipairs(reps) do s = ReplaceWord(s, r.old, r.tok) end
        if s:find("\001", 1, true) then s = s:gsub("\001%d+\001", final) end
        return s
    end
    local seen = {}
    local function CopyRenamed(v, depth)
        if type(v) == "string" then return Str(v) end
        if type(v) ~= "table" then return v end
        if seen[v] or depth > 40 then return nil end
        seen[v] = true
        local t = {}
        for k, x in pairs(v) do t[type(k) == "string" and Str(k) or k] = CopyRenamed(x, depth + 1) end
        seen[v] = nil
        return t
    end
    local out = CopyRenamed(data, 0)
    -- the team records: the placeholder is the whole name
    for _, new in pairs(newOf) do
        local m = out.team and out.team[new]
        if type(m) == "table" then m.name, m.last = new, nil end
    end
    return out, profileName and Str(profileName) or nil
end

-- returns name, data (or nil)
function ns.ParseExport(str)
    local body = ns.Trim(str):match("^MMT1:(.*)$")
    if not body then return nil end
    local t = ns.Deserialize(body)
    if type(t) ~= "table" then return nil end
    if type(t.name) == "string" and type(t.data) == "table" then
        return t.name, t.data, type(t.modules) == "table" and t.modules or nil,
            type(t.moduleSettings) == "table" and t.moduleSettings or nil,
            type(t.look) == "table" and t.look or nil
    end
    if t.team or t.xp then return "Imported", t end -- 2.0.0 test build strings
    return nil
end

-- Stores data under name (overwrites a profile with that name) and,
-- if wanted, activates it for this character.
function ns.ImportProfile(name, data, activate)
    name = ns.Trim(name)
    if name == "" or type(data) ~= "table" then return false end
    MMTDB.profiles[name] = data
    ConvertProfile(data)
    MergeDefaults(data, ns.defaults)
    if activate then ns.SetProfile(name) end
    return true
end

-- Core settings only (team sync): the active profile without the settings
-- of modules. Window positions (XP, distance) are part of it.
-- withModules: also the settings of the modules that share theirs (sync = true);
-- the team sync adds them when every recipient is in the guild (guild channel)
function ns.ExportCoreSettings(withModules)
    local data = {}
    for k, v in pairs(ns.db) do
        if k ~= "modules" then data[k] = Copy(v) end
    end
    local moduleSettings
    if withModules and ns.SyncableModules then
        moduleSettings = {}
        for _, m in ipairs(ns.SyncableModules()) do moduleSettings[m.name] = m:SyncData() end
    end
    -- the on/off state of the modules and the settings window's look go along
    -- (applied, not stored in the profile)
    return "MMT1:" .. ns.Serialize({ name = ns.CurrentProfileName(), data = data, core = true,
        modules = ns.ModuleStates and ns.ModuleStates() or nil, moduleSettings = moduleSettings,
        look = ns.ExportLook() })
end

-- the settings window's look (Help > Appearance) and scale: kept per account in MMTDB,
-- sent along with the profile sync
function ns.ExportLook()
    return { background = MMTDB.configBackground or "NONE", artAlpha = ns.ArtAlpha and ns.ArtAlpha() or nil,
        artTint = not (MMTDB.configArtTint == false), scale = ns.ConfigScale and ns.ConfigScale() or nil }
end

-- applies a synced look; returns true when something changed
function ns.ApplyLook(look)
    if type(look) ~= "table" then return false end
    local before = ns.Serialize(ns.ExportLook())
    if type(look.background) == "string" then
        local known = look.background == "NONE"
        for _, b in ipairs(ns.BACKGROUNDS or {}) do if b.value == look.background then known = true end end
        if known and ns.SetConfigBackground then ns.SetConfigBackground(look.background) end
    end
    local alpha = tonumber(look.artAlpha)
    if alpha and alpha >= 0.1 and alpha <= 0.6 and ns.SetArtAlpha then ns.SetArtAlpha(alpha) end
    if type(look.artTint) == "boolean" and ns.SetArtTint then ns.SetArtTint(look.artTint) end
    local scale = tonumber(look.scale)
    if scale and ns.SetConfigScale then ns.SetConfigScale(scale) end
    return ns.Serialize(ns.ExportLook()) ~= before
end

-- Stores core settings under name and activates that profile. The module
-- settings already in a profile of that name stay as they are (also when
-- an older MMT sent its full profile).
function ns.ImportCoreSettings(name, data)
    name = ns.Trim(name)
    if name == "" or type(data) ~= "table" then return false end
    local existing = MMTDB.profiles[name]
    data.modules = (existing and type(existing.modules) == "table") and Copy(existing.modules) or {}
    return ns.ImportProfile(name, data, true)
end

---------------------------------------------------------------------------
-- Init & migration
---------------------------------------------------------------------------
local OMT_KEYS = { "shiftBypass", "quests", "gossip", "merchant", "invites", "camera", "distance" }

local function MigrateOMT()
    if MMTDB.migratedOMT or type(OMTDB) ~= "table" or next(OMTDB) == nil then return end
    local target = MMTDB.profiles[DEFAULT]
    for _, key in ipairs(OMT_KEYS) do
        if OMTDB[key] ~= nil then target[key] = Copy(OMTDB[key]) end
    end
    MMTDB.migratedOMT = true
    ns.migratedOMT = true
    ns.justMigrated = true
end

function ns.InitDB()
    MMTDB = MMTDB or {}
    MMTDB.profiles = MMTDB.profiles or {}
    MMTDB.profileKeys = MMTDB.profileKeys or {}
    -- 2.0.0 test build used "chars" with "First Last" keys
    if type(MMTDB.chars) == "table" then
        for char, profile in pairs(MMTDB.chars) do
            local key = KeyFromName(char)
            MMTDB.profileKeys[key] = MMTDB.profileKeys[key] or profile
        end
        MMTDB.chars = nil
    end
    -- MMT 0.3.0: Item Compare's equipment database lived in MMTDB.equipment
    if type(MMTDB.equipment) == "table" then
        MMTDB.moduleData = MMTDB.moduleData or {}
        MMTDB.moduleData.ItemCompare = MMTDB.moduleData.ItemCompare or {}
        MMTDB.moduleData.ItemCompare.equipment = MMTDB.moduleData.ItemCompare.equipment or MMTDB.equipment
        MMTDB.equipment = nil
    end
    MMTDB.profiles[DEFAULT] = MMTDB.profiles[DEFAULT] or {}
    Activate(DEFAULT) -- usable right away; the character's profile is picked at login
end

function ns.SelectCharacterProfile()
    MigrateOMT() -- OMT loads after MMT, so its settings are only available now
    local key = CharKey()
    local name = MMTDB.profileKeys[key] or DEFAULT
    if not MMTDB.profiles[name] then name = DEFAULT end
    MMTDB.profileKeys[key] = name
    Activate(name)
    if ns.migratedOMT then
        ns.Print("Your OMT settings were moved into the \"Default\" profile. You can now disable OMT.")
        ns.migratedOMT = nil
    end
end
