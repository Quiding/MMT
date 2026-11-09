-- MMT: privacy. Replaces the names of your team's characters in text with the
-- name chosen in Team > Privacy ("Apple", "Bikini", "Druid 1", "Slot 2").
--
--   * ns.ReplaceNames(text, forDebug): used for debug logs and reports when
--     "Keep full names in debug logs" is off.
--   * "Hide names outside MMT too": chat (every chat window), unit frames
--     (player, target, focus, target of target, party, raid), nameplates,
--     unit tooltips, lines other addons add to any tooltip (Syndicator's
--     character counts on item tooltips, ...) and any text other addons show
--     in their own frames (raid
--     frames of other addons), as far as the game allows: values the game
--     hands out as secrets can't be read and stay as they are. One exception:
--     EllesmereUI's damage meter, whose rows get other players' names as
--     secrets in combat - a row whose class only one team member in the
--     group has gets that member's name (see "Damage meter rows" below). The names the
--     game draws above characters in the world (nameplates off) can't be
--     changed: friendly nameplates are switched on or those names off instead
--     ("Name above characters").
--
-- Only what is shown changes: player links in chat keep the real name, so
-- clicking a name still whispers the right character. Addon messages,
-- macros, invites and whispers always use the real names.

local _, ns = ...

local function Settings() return ns.db and ns.db.privacy end

local function Active()
    local p = Settings()
    return p and p.hideOutside and p.nameMode ~= "FULL"
end
-- "Hide names outside MMT too" in effect (true/false)
function ns.PrivacyHidesOutside() return Active() and true or false end

---------------------------------------------------------------------------
-- Text replacement
---------------------------------------------------------------------------
local LETTER = "%w\128-\255"
local function Esc(s) return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")) end
-- upper / lower case don't matter: the game reports "Lookingglass", other
-- addons may show "LookingGlass"
local function Caseless(pattern)
    return (pattern:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end))
end

-- { pattern, replacement } for every spelling of every team name, longest first
local function Rules(forDebug)
    local rules = {}
    local team = ns.db and ns.db.team
    if not team then return rules end
    local mode = Settings() and Settings().nameMode or "FIRST"
    for key, m in pairs(team) do
        local first, last = ns.RealFirst(key), ns.RealLast(key)
        local alias
        if forDebug and mode == "FULL" then alias = ns.NameFor(key, "SLOT")
        else alias = ns.ShownName(key) end
        local function Add(text)
            if text and text ~= "" and text ~= alias then
                rules[#rules + 1] = { text = text, alias = alias }
            end
        end
        if first and last then
            Add(first .. " " .. last)
            Add(first .. "-" .. last)
            if forDebug then
                Add(first .. "<20>" .. last)   -- ns.Repr spellings
                Add(first .. "<2d>" .. last)
            end
        end
        Add(first)
        Add(last)
    end
    table.sort(rules, function(a, b) return #a.text > #b.text end)
    for _, r in ipairs(rules) do
        r.pattern = "%f[" .. LETTER .. "]" .. Caseless(Esc(r.text)) .. "%f[^" .. LETTER .. "]"
        r.repl = r.alias:gsub("%%", "%%%%")
    end
    -- first name + space/hyphen + the start of the last name: other addons
    -- shorten names to fit ("John Multiboxe", "John Mul", "John M.").
    -- These go first, before the single names.
    local shortened = {}
    for key in pairs(team) do
        local first, last = ns.RealFirst(key), ns.RealLast(key)
        if first and last and first ~= "" and last ~= "" then
            local alias = (forDebug and mode == "FULL") and ns.NameFor(key, "SLOT") or ns.ShownName(key)
            local lastLower = last:lower()
            shortened[#shortened + 1] = {
                text = first .. " " .. last, alias = alias, first = #first,
                pattern = "%f[" .. LETTER .. "]" .. Caseless(Esc(first)) .. "[%s%-]+([" .. LETTER .. "]+)%f[^" .. LETTER .. "]",
                repl = function(part)
                    if lastLower:sub(1, #part) == part:lower() then return alias end
                end,
            }
        end
    end
    table.sort(shortened, function(a, b) return a.first > b.first end)
    for i = #shortened, 1, -1 do table.insert(rules, 1, shortened[i]) end
    return rules
end

local cache = {}
local function CachedRules(forDebug)
    local k = forDebug and "debug" or "show"
    if not cache[k] then
        local rules = Rules(forDebug)
        -- quick test: the names that must appear for any rule to match
        local needles, seen = {}, {}
        for _, r in ipairs(rules) do
            local word = (r.text:match("^[^%s%-<]+") or r.text):lower()
            if not seen[word] then seen[word] = true; needles[#needles + 1] = Caseless(Esc(word)) end
        end
        rules.needles = needles
        cache[k] = rules
    end
    return cache[k]
end
local Reapply   -- below
-- the setting, the team or a class changed: new rules, and everything shown again
-- hiding on/off as at login: a profile switch or a synced profile that
-- changes it needs a reload for other addons (said once in chat)
-- The same for "Show characters by" while hiding: other addons' frames keep
-- the names they were given until a reload.
local activeAtLogin, modeAtLogin, reloadSaid
ns.OnLogin(function()
    activeAtLogin, reloadSaid = Active() and true or false, false
    modeAtLogin = Settings() and Settings().nameMode
end)
local function CheckReload()
    if activeAtLogin == nil or reloadSaid or ns.privacyReloading then return end
    local now = Active() and true or false
    if now ~= activeAtLogin or (now and Settings().nameMode ~= modeAtLogin) then
        reloadSaid = true
        ns.Print("Privacy names changed (\"Hide names outside MMT too\" or \"Show characters by\"): reload the UI (/reload) so other addons follow.")
    end
end

---------------------------------------------------------------------------
-- Names above characters in the 3D world: the game draws them itself, no
-- addon can change that text. While hiding, Team > Privacy > "Name above
-- characters" picks what to do:
--   NAMEPLATES: "Always show nameplates", friendly player nameplates and
--               friendly player names on (Blizzard's or an addon's nameplates, their names
--               are replaced like all other text); your own character has no
--               nameplate, so its name above it is switched off
--   HIDE:       "Always show nameplates", friendly player nameplates and the
--               names of your own character and all friendly players off
-- The values before are kept per character (MMTDB.worldNames) and put back
-- when hiding is off again (or the other choice is made), unless they were
-- changed by hand in the meantime.
---------------------------------------------------------------------------
local WORLD_CVARS = {
    -- Always Show Nameplates, Friendly Player Nameplates (Options > Nameplates;
    -- nameplateShowFriends is the older clients' name, only used where it
    -- exists), the friendly player names drawn by the game (Interface > Names)
    -- and your own name (your character has no nameplate)
    NAMEPLATES = { nameplateShowAll = "1", nameplateShowFriendlyPlayers = "1", nameplateShowFriends = "1",
                   UnitNameFriendlyPlayerName = "1", UnitNameOwn = "0" },
    HIDE       = { nameplateShowAll = "0", nameplateShowFriendlyPlayers = "0", nameplateShowFriends = "0",
                   UnitNameFriendlyPlayerName = "0", UnitNameOwn = "0" },
}
local function GetCV(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    if GetCVar then return GetCVar(name) end
end
local function SetCV(name, value)
    local ok
    if C_CVar and C_CVar.SetCVar then ok = pcall(C_CVar.SetCVar, name, value)
    elseif SetCVar then ok = pcall(SetCVar, name, value) end
    return ok
end
local worldPending
function ns.ApplyWorldNames()
    if not MMTDB or not ns.PlayerFull then return end
    if InCombatLockdown and InCombatLockdown() then worldPending = true return end
    worldPending = nil
    MMTDB.worldNames = MMTDB.worldNames or {}
    local me = ns.PlayerFull()
    -- saved[cvar] = { old = value before, set = value MMT put in }
    local saved = MMTDB.worldNames[me] or {}
    local p = Settings()
    local want = Active() and (WORLD_CVARS[p.worldNames] or WORLD_CVARS.NAMEPLATES) or {}
    -- back what the current choice doesn't need
    for cvar, s in pairs(saved) do
        if want[cvar] == nil then
            if type(s) == "table" and GetCV(cvar) == s.set then SetCV(cvar, s.old) end
            saved[cvar] = nil
        end
    end
    for cvar, value in pairs(want) do
        local cur = GetCV(cvar)
        if cur ~= nil and cur ~= value then
            if saved[cvar] then saved[cvar].set = value   -- the value before MMT stays
            else saved[cvar] = { old = cur, set = value } end
            SetCV(cvar, value)
        end
    end
    MMTDB.worldNames[me] = next(saved) and saved or nil
end
ns.OnLogin(function() ns.ApplyWorldNames() end)
ns.On("PLAYER_REGEN_ENABLED", function() if worldPending then ns.ApplyWorldNames() end end)

function ns.PrivacyChanged()
    CheckReload()
    if ns.ApplyWorldNames then ns.ApplyWorldNames() end
    cache = {}
    if ns.RefreshNameFrames then ns.RefreshNameFrames() end
    if Reapply then Reapply() end
end
ns.Listen("TEAM_CHANGED", function() ns.PrivacyChanged() end)
ns.Listen("PROFILE_CHANGED", function() ns.PrivacyChanged() end)
-- a class learned later turns "Slot 4" into "Druid 3"
local knownClass = {}
ns.Listen("XP_RECEIVED", function(key, sender, st)
    local class = st and st.class
    if class and class ~= "" and knownClass[key] ~= class then
        knownClass[key] = class
        ns.PrivacyChanged()
    end
end)

local function ReplacePlain(text, rules)
    if text == "" then return text end
    for _, r in ipairs(rules) do text = text:gsub(r.pattern, r.repl) end
    return text
end

-- escape sequences that are not shown text: links (data part), textures,
-- atlases, Battle.net names, colour codes, "|r", "||", "|n". They separate
-- words, so "|cffaad372John Multiboxer|r" is found as a whole name.
local ESCAPES = { "^|H.-|h", "^|T.-|t", "^|A.-|a", "^|K.-|k", "^|c%x%x%x%x%x%x%x%x", "^|cn[^:]*:", "^|r", "^||", "^|n" }

local function Contains(text, needles)
    for _, n in ipairs(needles) do
        if text:find(n) then return true end
    end
    return false
end

-- replaces the names in shown text; escape sequences stay as they are
function ns.ReplaceNames(text, forDebug)
    if type(text) ~= "string" or ns.IsSecret(text) or text == "" then return text end
    local rules = CachedRules(forDebug)
    if #rules == 0 or not Contains(text, rules.needles) then return text end
    local out, pos, len = {}, 1, #text
    while pos <= len do
        local bar = text:find("|", pos, true)
        if not bar then break end
        out[#out + 1] = ReplacePlain(text:sub(pos, bar - 1), rules)
        local stop
        for _, pattern in ipairs(ESCAPES) do
            local _, e = text:find(pattern, bar)
            if e then stop = e break end
        end
        stop = stop or bar
        out[#out + 1] = text:sub(bar, stop)
        pos = stop + 1
    end
    out[#out + 1] = ReplacePlain(text:sub(pos), rules)
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Chat: every chat window shows the replaced text
---------------------------------------------------------------------------
local wrapped = {}
-- replaced chat line -> original line (the last 500), so a changed setting can redo them
local chatOriginal, chatOrder = {}, {}
local function RememberChat(shown, orig)
    if chatOriginal[shown] == nil then
        chatOrder[#chatOrder + 1] = shown
        if #chatOrder > 500 then chatOriginal[table.remove(chatOrder, 1)] = nil end
    end
    chatOriginal[shown] = orig
end

local function WrapChatFrame(frame)
    if not frame or wrapped[frame] or type(frame.AddMessage) ~= "function" then return end
    wrapped[frame] = true
    local original = frame.AddMessage
    frame.AddMessage = function(self, text, ...)
        if Active() and type(text) == "string" and not ns.IsSecret(text) then
            local ok, replaced = pcall(ns.ReplaceNames, text)
            if ok and replaced ~= text then
                RememberChat(replaced, text)
                text = replaced
            end
        end
        return original(self, text, ...)
    end
end

-- lines already in the chat windows: shown again with the current setting
-- (original names back when the option is off); needs TransformMessages
local function ReapplyChat()
    for frame in pairs(wrapped) do
        if frame.TransformMessages then
            pcall(frame.TransformMessages, frame,
                function(entry)
                    return type(entry) == "table" and type(entry.message) == "string" and not ns.IsSecret(entry.message)
                end,
                function(entry)
                    local orig = chatOriginal[entry.message] or entry.message
                    local new = Active() and ns.ReplaceNames(orig) or orig
                    if new ~= entry.message then
                        entry.message = new
                        if new ~= orig then RememberChat(new, orig) end
                    end
                end)
        end
    end
end

local function WrapAllChatFrames()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do WrapChatFrame(_G["ChatFrame" .. i]) end
    for _, name in ipairs(CHAT_FRAMES or {}) do WrapChatFrame(_G[name]) end
end

---------------------------------------------------------------------------
-- Unit frames, nameplates
---------------------------------------------------------------------------
local function NameText(frame)
    if not frame then return nil end
    local content = frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
    local fs = frame.name or frame.Name or (content and content.Name)
    if not fs and frame.GetName and frame:GetName() then
        fs = _G[frame:GetName() .. "Name"] or _G[frame:GetName() .. "TextureFrameName"]
    end
    if fs and fs.GetText and fs.SetText then return fs end
end

local AfterSetText   -- below: replaces and remembers the original text
local function FixFrame(frame)
    if not Active() then return end
    local fs = NameText(frame)
    if fs then AfterSetText(fs, nil) end
end

local FRAMES = { "PlayerFrame", "TargetFrame", "FocusFrame", "TargetFrameToT", "FocusFrameToT",
    "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }

function ns.RefreshNameFrames()
    if not Active() then return end
    for _, name in ipairs(FRAMES) do FixFrame(_G[name]) end
    if PlayerName then FixFrame({ name = PlayerName }) end
    local party = _G.PartyFrame
    if party then
        for i = 1, 4 do FixFrame(party["MemberFrame" .. i]) end
    end
end

local function RefreshSoon() C_Timer.After(0, ns.RefreshNameFrames) end

if hooksecurefunc then
    if UnitFrame_Update then hooksecurefunc("UnitFrame_Update", function(self) FixFrame(self) end) end
    if CompactUnitFrame_UpdateName then
        hooksecurefunc("CompactUnitFrame_UpdateName", function(self) FixFrame(self) end)   -- raid frames, nameplates
    end
    if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", function() C_Timer.After(0, WrapAllChatFrames) end) end
end

for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_NAME_UPDATE",
    "PLAYER_ENTERING_WORLD" }) do
    ns.On(e, RefreshSoon)
end

---------------------------------------------------------------------------
-- Every other text in the interface (unit and raid frames of other addons,
-- e.g. Ellesmere): after any FontString:SetText / SetFormattedText the text
-- is checked. Cheap when no team name is in it (a few plain searches).
---------------------------------------------------------------------------
local busy = false
-- texts MMT replaced: [fontString] = { orig = text before, shown = text now }
local tracked = setmetatable({}, { __mode = "k" })

local function SetQuietly(fs, text)
    busy = true
    pcall(fs.SetText, fs, text)
    busy = false
end

---------------------------------------------------------------------------
-- Damage meter rows (EllesmereUIDamageMeters). In combat the game gives the
-- meter other players' names as secrets: they can't be read, so the text
-- replacement can't see them. The row's class can still be seen on the row
-- itself, painted from the never-secret classFilename before the name: its icon
-- (the class sheet "UI-CHARACTERCREATE-CLASSES" at that class's CLASS_ICON_TCOORDS)
-- or else its bar colour (EllesmereUI's class colour). When exactly one member
-- of the group (not you - your own row is never secret) has that class and it's a
-- team member, the row gets that member's name. Two of a class (team or not),
-- or a stranger of that class: left as it is.
-- A row: label font string (left-aligned; the amount, right-aligned, is secret too and stays) -> text frame -> bar.fill (StatusBar, holds the
-- icon texture) -> bar.row -> ... -> the window "EllesmereUIDMFrame<n>".
---------------------------------------------------------------------------
local meterSet = setmetatable({}, { __mode = "k" })       -- [fontString] = name we put there
local meterPending = setmetatable({}, { __mode = "k" })
local meterSaid = setmetatable({}, { __mode = "k" })     -- [fontString] = when the debug line said why

-- the bar (StatusBar) of the EllesmereUI meter row this font string is the name of, else nil
local function MeterFill(fs)
    -- only the name: left-aligned (the amount on the right is secret in combat too; the rank isn't)
    local okJ, justify = pcall(fs.GetJustifyH, fs)
    if not okJ or justify ~= "LEFT" then return nil end
    local ok, tf = pcall(fs.GetParent, fs)
    if not ok or type(tf) ~= "table" or not tf.GetParent then return nil end
    local ok2, fill = pcall(tf.GetParent, tf)
    if not ok2 or type(fill) ~= "table" or not fill.GetStatusBarColor then return nil end
    local f, n = fill, 0
    while f and n < 12 do
        n = n + 1
        local okN, name = pcall(f.GetName, f)
        if okN and type(name) == "string" and not ns.IsSecret(name) and name:find("^EllesmereUIDMFrame%d+$") then return fill end
        local okP, parent = pcall(f.GetParent, f)
        if not okP or parent == UIParent then return nil end
        f = parent
    end
end

-- the class sheet's texture id, as the game reports it for a texture showing it
local sheetID
local function SheetID()
    if sheetID == nil then
        sheetID = false
        local t = UIParent and UIParent.CreateTexture and UIParent:CreateTexture()
        if t then
            t:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            sheetID = t:GetTexture() or false
            t:Hide()
        end
    end
    return sheetID
end

local function Plain(v) return v ~= nil and not ns.IsSecret(v) end
local function Near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.012 end

-- does this row show that class? its class icon first, else the bar colour
local function RowShowsClass(fill, class)
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    local sheet = SheetID()
    local okR, regions = pcall(function() return { fill:GetRegions() } end)
    local sawIcon = false
    if okR and coords and sheet then
        for _, r in ipairs(regions) do
            if r.GetTexCoord and r.GetTexture and r:IsShown() then
                local okT, tex = pcall(r.GetTexture, r)
                if okT and Plain(tex) and tex == sheet then
                    sawIcon = true
                    local okC, l, t, _, _, _, _, rr, b = pcall(r.GetTexCoord, r)
                    if okC and Plain(l) and Plain(rr) and Plain(t) and Plain(b) then
                        local cx, cy = (l + rr) / 2, (t + b) / 2
                        if cx > coords[1] and cx < coords[2] and cy > coords[3] and cy < coords[4] then return true end
                    end
                end
            end
        end
    end
    if sawIcon then return false end   -- the icon shows another class
    local okB, r, g, b = pcall(fill.GetStatusBarColor, fill)
    if not okB or not (Plain(r) and Plain(g) and Plain(b)) then return false end
    local cols = {}
    local EUI = rawget(_G, "EllesmereUI")
    if EUI and EUI.GetClassColor then
        local okE, c = pcall(EUI.GetClassColor, class)
        if okE and type(c) == "table" then cols[#cols + 1] = c end
    end
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then cols[#cols + 1] = RAID_CLASS_COLORS[class] end
    for _, c in ipairs(cols) do
        if Near(r, c.r) and Near(g, c.g) and Near(b, c.b) then return true end
    end
    return false
end

-- everyone in the group (not you) by class: { [class] = team key }, false for a class two of them
-- have - team members or not (a stranger's row must never get a team member's name). Someone
-- whose class can't be told: no class is sure, nothing is replaced.
local function GroupedByClass()
    local by = {}
    if not ns.db then return by end
    for _, unit in ipairs(ns.GroupUnits()) do
        local _, _, full = ns.SplitUnit(unit)
        local key = full and ns.Resolve(full)
        local m = key and ns.db.team[key]
        local ok, _, class = pcall(UnitClass, unit)
        if not ok or type(class) ~= "string" or ns.IsSecret(class) then class = m and m.class end
        if type(class) ~= "string" then return {} end
        if not (key and ns.IsSelf(key)) then
            local who = m and key or false   -- false: not on the team
            if by[class] ~= nil and by[class] ~= who then by[class] = false else by[class] = who end
        end
    end
    return by
end

-- the one team member in the group whose class this row shows, else nil
local function MemberForRow(fill)
    local found
    for class, key in pairs(GroupedByClass()) do
        if RowShowsClass(fill, class) then
            if not key or found then return nil end   -- two of that class, or two classes match
            found = key
        end
    end
    return found
end

local FixMeterRow
FixMeterRow = function(fs, later)
    local fill = MeterFill(fs)
    if not fill then return false end
    local key = MemberForRow(fill)
    if not key and not later then
        local now = GetTime and GetTime() or 0
        if now - (meterSaid[fs] or -99) > 10 then   -- why a row keeps its name (/mmt debug)
            meterSaid[fs] = now
            local classes = {}
            for class, k in pairs(GroupedByClass()) do classes[#classes + 1] = class .. (k and "" or "(unsure)") end
            ns.Debug("privacy: meter row left as it is - team classes in the group: %s", table.concat(classes, ", "))
        end
    end
    if key then
        local name = ns.ShownName(key)
        local ok, cur = pcall(fs.GetText, fs)
        if not (ok and not ns.IsSecret(cur) and cur == name) then SetQuietly(fs, name) end
        meterSet[fs] = name
    end
    if not later and not meterPending[fs] then
        meterPending[fs] = true
        C_Timer.After(0, function()
            meterPending[fs] = nil
            if not Active() then return end
            local ok, cur = pcall(fs.GetText, fs)
            -- still the secret name, or the name we put there: again (the row may have changed)
            if ok and (ns.IsSecret(cur) or cur == meterSet[fs]) then FixMeterRow(fs, true) end
        end)
    end
    return true
end
ns.PrivacyMeter = { MemberForRow = MemberForRow, RowShowsClass = RowShowsClass, FixMeterRow = FixMeterRow }   -- (tests / debug)

AfterSetText = function(fs, text)
    if busy or not Active() then return end
    if text == nil then text = fs:GetText() end
    if ns.IsSecret(text) then FixMeterRow(fs) return end
    if type(text) ~= "string" then return end
    local new = ns.ReplaceNames(text)
    if new ~= text then
        tracked[fs] = { orig = text, shown = new }
        SetQuietly(fs, new)
    elseif tracked[fs] and tracked[fs].shown ~= text then
        tracked[fs] = nil   -- new text without names
    end
end

-- everything MMT replaced: again with the current setting, or back to the
-- original when the option is off; chat history too
Reapply = function()
    for fs, t in pairs(tracked) do
        local ok, current = pcall(fs.GetText, fs)
        if ok and current == t.shown then
            local new = Active() and ns.ReplaceNames(t.orig) or t.orig
            if new ~= current then SetQuietly(fs, new) end
            t.shown = new   -- kept when restored, so switching on again redoes it
        else
            tracked[fs] = nil   -- the frame shows something else by now
        end
    end
    ReapplyChat()
end

do
    local probe = UIParent and UIParent.CreateFontString and UIParent:CreateFontString()
    local meta = probe and getmetatable(probe)
    local methods = meta and meta.__index
    if hooksecurefunc and type(methods) == "table" then
        if methods.SetText then hooksecurefunc(methods, "SetText", function(fs, text) AfterSetText(fs, text) end) end
        if methods.SetFormattedText then hooksecurefunc(methods, "SetFormattedText", function(fs) AfterSetText(fs, nil) end) end
    end
end

---------------------------------------------------------------------------
-- Unit tooltips
---------------------------------------------------------------------------
-- every line, both sides: the name lines on top, and lines further down such as
-- "Master Looter: <name>" and "Loot: <name>" on NPC tooltips
local function FixTooltip(tt)
    if not Active() or not tt or not tt.NumLines or not tt.GetName or not tt:GetName() then return end
    local name = tt:GetName()
    for i = 1, tt:NumLines() or 0 do
        for _, side in ipairs({ "TextLeft", "TextRight" }) do
            local fs = _G[name .. side .. i]
            local text = fs and fs:GetText()
            if type(text) == "string" and not ns.IsSecret(text) then
                local new = ns.ReplaceNames(text)
                if new ~= text then fs:SetText(new) end
            end
        end
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, FixTooltip)
elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", FixTooltip)
end

---------------------------------------------------------------------------
-- Lines other addons add to any tooltip (item tooltips too): Syndicator's /
-- Baganator's "Salsa Berry-PvP: Bags 56", Questie, ... The game fills
-- tooltip lines itself, so the FontString hook above never sees them: after
-- every AddLine / AddDoubleLine the line just added is checked (both sides).
---------------------------------------------------------------------------
local function FixLastLine(tt)
    if not Active() or not tt or not tt.NumLines or not tt.GetName then return end
    local name, n = tt:GetName(), tt:NumLines()
    if not name or not n or n < 1 then return end
    for _, side in ipairs({ "TextLeft", "TextRight" }) do
        local fs = _G[name .. side .. n]
        local text = fs and fs:GetText()
        if type(text) == "string" and not ns.IsSecret(text) then
            local new = ns.ReplaceNames(text)
            if new ~= text then fs:SetText(new) end
        end
    end
end

do
    -- every tooltip shares these methods (GameTooltip, ItemRefTooltip, the shopping tooltips, addons' own)
    local meta = GameTooltip and getmetatable(GameTooltip)
    local methods = meta and meta.__index
    if hooksecurefunc and type(methods) == "table" then
        if methods.AddLine then hooksecurefunc(methods, "AddLine", FixLastLine) end
        if methods.AddDoubleLine then hooksecurefunc(methods, "AddDoubleLine", FixLastLine) end
    end
end

ns.OnLogin(function()
    WrapAllChatFrames()
    RefreshSoon()
end)
ns.On("UPDATE_CHAT_WINDOWS", function() WrapAllChatFrames() end)
