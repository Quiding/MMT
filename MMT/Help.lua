-- MMT: Help page (CORE section): debug tools with a how-to, short guides for
-- writing modules and using the team communication, and the look of this window.

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT
local H = ns.ConfigHelpers
local PAGE_W, COL_W, COL2_X = H.PAGE_W, H.COL_W, H.COL2_X

---------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------
local DEBUG_STEPS = table.concat({
    "1. Tick \"Debug log\" (or type /mmt debug).",
    "2. Press \"Clear log\" so the report only shows the new problem.",
    "3. Do what goes wrong: add the team, open a trade, press the Item Compare key, ...",
    "4. For team problems press \"Ping team\" and wait 5 seconds.",
    "5. Press \"Debug report\", then Select all and Ctrl+C.",
    "6. Paste it to Claude. For team problems, do steps 1-5 on every client.",
}, "\n")

local DEBUG_COMMANDS = table.concat({
    "/mmt debug                debug log on/off",
    "/mmt debug dump           copyable report",
    "/mmt debug log | clear    show or clear the log",
    "/mmt debug chat           also print log lines to chat",
    "/mmt debug name <text>    how a typed name is understood",
    "/mmt ping                 test reaching every team member",
}, "\n")

local MODULE_TEXT = "A module is its own addon in Interface/AddOns, next to MMT. It shows up under MODULES and in the game's AddOns list. Copy the example below into a folder MMT_Example (two files), then restart the game completely, because new folders only show up after a restart."

local MODULE_CODE = [[
-- MMT_Example/MMT_Example.toc ------------------------------
## Interface: 16001
## Title: MMT - Example
## Notes: One line about the module.
## Version: 1.0.0
## Author: YourName
## X-Repository: https://github.com/you/your-repo
## Dependencies: MMT
## DefaultState: disabled
## X-MMT-DefaultState: disabled
## X-MMT-Module: 1
## X-MMT-Title: Example

Module.lua

-- MMT_Example/Module.lua -----------------------------------
local MMT = MMT
local M = MMT.NewModule({
    name = "Example",                 -- unique; also the settings key
    title = "Example",
    description = "One line for Manage modules.",
    defaults = { greeting = true },   -- per profile, read/write M.db
    sync = true,                      -- optional: share M.db with the team
    syncExclude = { "point" },        -- optional: keys that stay per client
})

-- M.db     settings in the active profile (defaults merged in)
-- M.store  account-wide data (e.g. a database), kept across profiles

M.OnEnable = function(self) end   -- switched on (also at login)
M.OnDisable = function(self) end  -- switched off: hide frames, stop timers

-- game events and core callbacks only run while the module is on
M:On("PLAYER_LEVEL_UP", function(level)
    if M.db.greeting then MMT.Print("Level %d!", level) end
end)
M:Listen("TEAM_CHANGED", function() M:Debug("team changed") end)

-- optional settings page (shown under MODULES)
M.Page = function(self, page)
    local col = MMT.UI.Column(page, 0, 0, MMT.ConfigHelpers.COL_W)
    col:Header("Example")
    col:Check("Greeting on level up",
        function() return M.db.greeting end,
        function(v) M.db.greeting = v end)
end

-- Settings sync (with sync = true): the core adds a "Sync to team"
-- button in the bottom right of M.Page and /mmt sync example. Only M.db
-- is sent (never M.store); the recipient accepts in a dialog. Optional:
M.OnSyncReceived = function(self, from)   -- after the team's settings
    MMT.Print("Example settings from %s applied.", from or "?")
end
-- For a frame of your own: M:SyncButton(frame), or M:SyncToTeam().

-- optional lines for /mmt debug dump
M.Report = function(self, add)
    add("Example: greeting=" .. tostring(M.db.greeting))
end

-- Names: internally, characters are always addressed by their full name
-- (team key "First-Last"; messages, whispers, invites, unit lookups), so
-- features find the right character. Everything the player SEES uses the
-- privacy setting (Team > Privacy: first name by default, last or full
-- name, "Druid 1", "Slot 2"): MMT.ShownName(key) (MMT.FirstName and
-- MMT.FullDisplay do the same) in frames, chat lines, tooltips, warnings.
-- Real names only where the game needs them, e.g. macros:
-- MMT.RealName(key), MMT.RealFirst(key), MMT.RealLast(key).
-- Mouseover: MMT.HoverMember(frame, function() return key end).

-- Key bindings: a Bindings.xml in the module folder (not in the TOC) with
-- category="BINDING_CATEGORY_MMT" puts your keys into the key binding
-- group "MMT (Manage My Team)". Use your own header (header="MMT_EXAMPLE"
-- on the first binding; "MMT" is the core's) and set the texts in Lua:
--   <Binding name="MMT_EXAMPLE_HELLO" header="MMT_EXAMPLE"
--            category="BINDING_CATEGORY_MMT">MMT_ExampleHello()</Binding>
BINDING_HEADER_MMT_EXAMPLE = "Example"
BINDING_NAME_MMT_EXAMPLE_HELLO = "Say hello"
function MMT_ExampleHello() if M.enabled then MMT.Print("Hello!") end end

-- Reload: ReloadUI() is blocked for addons; MMT.UI.AskReload(text, before)
-- shows a dialog whose secure button runs /reload.

-- Useful core functions: MMT.Print, M:Debug, MMT.SortedMembers(),
-- MMT.IsOnline(key), MMT.IsSelf(key), MMT.PlayerFull(),
-- MMT.UI (widgets), MMT.Listen("PROFILE_CHANGED", fn)
]]

local COMM_TEXT = "Every client runs its own MMT. Everything is sent through one queue in the core, which keeps to the game's limits (about 10 messages per prefix, then 1 per second, on group and guild channels) and sends throttled messages again. Give important messages priority \"ALERT\", large ones \"BULK\" (default \"NORMAL\"). Long texts: MMT.SendLong splits them and the other side gets the whole text. Only messages from characters in this client's team are passed on. Keep single messages under 250 bytes and start them with your own tag. Leader tag (FTL): MMT.SendToLeader reaches only the FTL leader; scope \"FOLLOWERS\" reaches everybody but the leader. Each client checks against the leader it knows. MMT.SendAlert(msg) sends to the leader first, then to everybody else. Taken: XP, XP2, BYE, PING, PONG, SYNC, SYNCHI, SYNCACK, EQREQ, EQD, EQS, QNQ, QNA, LH, LHGO, LHC, QTREQ, QTS, QTD, QTAB, FOL, CC, TAXI, NOTE (also NOTE:WARN), MOUNT, DISMOUNT, DEATH, RELEASE, REVIVE, IBS, IBA, IBC, RMQ, RMA, MPT, FTL, FTLM, SHC, SHQ, STA, STQ, and the tag prefixes @L: and @F:. Prefixes in use: MMT, and MMTB to MMTB4 for large transfers."

local COMM_CODE = [[
-- send to the whole team (true = only members that are online);
-- optional priority: "ALERT" (first) | "NORMAL" | "BULK" (last)
MMT.SendToTeam("EXPING:" .. GetMoney(), true, "ALERT")

-- send to one character, e.g. answer the sender of a message
MMT.SendAddon("EXPONG:ok", "WHISPER", sender)

-- a long text (any size): sent in parts, arrives in one piece
-- (to the team, or to one character as second argument)
MMT.SendLong("EXDATA:" .. MMT.Serialize(myTable))

-- only for the FTL leader (returns "self" and sends nothing when this
-- character IS the leader: handle it here then)
if MMT.SendToLeader("EXCOME:" .. GetZoneText()) == "self" then
    -- this character leads
end
-- everybody but the leader: scope as 5th argument of SendToTeam
-- (4th of SendLong); "LEADER" works there too
MMT.SendToTeam("EXWAIT", true, "NORMAL", nil, "FOLLOWERS")

-- receive: called for every team message the core doesn't handle itself
--   key    team key of the sender ("First-Last")
--   sender name as the game reported it (use it to whisper back)
--   scope  nil, "LEADER" or "FOLLOWERS" (the tag is already removed
--          and messages not meant for this client never arrive)
M:Listen("TEAM_MESSAGE", function(key, sender, text, scope)
    local money = text:match("^EXPING:(%d+)$")
    if money then
        MMT.Print("%s has %s", MMT.FullDisplay(key),
            MMT.FormatMoney(tonumber(money)))
    end
end)

-- small values can ride on the heartbeat (every 30 s and on changes):
-- no extra messages. Values must not contain ":" "," or "=".
M:Heartbeat("ex", function() return UnitLevel("player") end)
M:Listen("XP_RECEIVED", function(key, sender, status)
    local value = status.ext.ex       -- string, or nil
end)

-- what the core already shares, in MMT.status[key]:
--   level, cur, max, rested, class, isMax, layer, layerKey,
--   money, free, slots, durAvg, durMin, online, sender

-- longer data (more than 250 bytes): split it into numbered parts
-- ("EXD:<id>:<part>:<total>:<data>") and put them together on
-- arrival. MMT_ItemCompare/Equipment.lua (EQS) shows how.
]]

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
-- read-only, selectable text box for code
local function CodeBox(parent, width, height, text)
    local area = UI.TextArea(parent, width, height)
    local e = area.edit
    e:SetFontObject("GameFontHighlightSmall")
    e:SetText(text)
    e:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(text) end
    end)
    return area
end

ns.RegisterPage("help", "Help", function(page)
    local Tile, Intro, TILE_W, TILE_GAP = H.Tile, H.Intro, H.TILE_W, H.TILE_GAP
    local TILE_IN = TILE_W - 16
    local X2 = TILE_W + TILE_GAP
    local TOP = Intro(page, "Tools for when something goes wrong, guides for writing your own modules, and the look of this window.")

    -- sub pages as a tab strip: the chosen one in the accent colour, underlined
    local panels, buttons = {}, {}
    local function Show(key)
        for k, p in pairs(panels) do p:SetShown(k == key) end
        for k, b in pairs(buttons) do
            local on = k == key
            b.label:SetTextColor(on and A[1] or 0.7, on and A[2] or 0.7, on and A[3] or 0.7)
            b.bar:SetShown(on)
        end
    end
    local tabs = { { "debug", "Debugging", "INV_Misc_Wrench_01" }, { "modules", "Writing modules", "Trade_Engineering" },
                   { "comm", "Team communication", "Ability_Warrior_BattleShout" }, { "look", "Appearance", "INV_Misc_Ribbon_01" } }
    local TAB_W = math.floor((PAGE_W - 3 * 6) / 4)
    local strip = page:CreateTexture(nil, "ARTWORK")
    strip:SetColorTexture(1, 1, 1, 0.08)
    strip:SetHeight(1)
    strip:SetPoint("TOPLEFT", 0, TOP - 26)
    strip:SetPoint("TOPRIGHT", 0, TOP - 26)
    local PANEL_Y = TOP - 34
    local PANEL_H = 564 + PANEL_Y
    for i, t in ipairs(tabs) do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(TAB_W, 26)
        b:SetPoint("TOPLEFT", (i - 1) * (TAB_W + 6), TOP)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.04)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 6, 0)
        icon:SetTexture("Interface\\Icons\\" .. t[3])
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.label = UI.Label(b, t[2], "GameFontNormal")
        b.label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        b.bar = b:CreateTexture(nil, "OVERLAY")
        b.bar:SetColorTexture(A[1], A[2], A[3], 0.9)
        b.bar:SetHeight(2)
        b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetPoint("BOTTOMRIGHT")
        b:SetScript("OnClick", function() Show(t[1]) end)
        buttons[t[1]] = b
        local p = CreateFrame("Frame", nil, page)
        p:SetPoint("TOPLEFT", 0, PANEL_Y)
        p:SetSize(PAGE_W, PANEL_H)
        panels[t[1]] = p
    end

    -- Debugging: tools and actions side by side, the how-to below -----------------------
    local d = panels.debug
    local TOOLS_H = 42 + 3 * UI.ROW + 12
    local _, L = Tile(d, 0, 0, TILE_W, TOOLS_H, "Debug Tools", "Interface\\Icons\\INV_Misc_Wrench_01")
    L:Check("Debug log", function() return MMTDB.debug end, function(v) MMTDB.debug = v end,
        "Logs what MMT detects and does. The log keeps the last 300 lines.")
    L:Check("Also print log lines to chat", function() return MMTDB.debugChat end,
        function(v) MMTDB.debugChat = v end)
    L:Check("Debug mode (ignore online requirements)", function() return ns.DebugMode() end,
        function(v) ns.SetDebugMode(v) end,
        "Shows every team member where MMT normally shows only those online with MMT: the XP window (offline members in grey, with their last known values) and the Quest Tracker. Only for testing: at every login MMT asks whether to switch it off.")
    local at, R = Tile(d, X2, 0, TILE_W, TOOLS_H, "Actions", "Interface\\Icons\\INV_Misc_Note_01")
    local half = math.floor((TILE_IN - 8) / 2)
    local report = UI.Button(at, half, "Debug report", function() ns.HandleDebugCommand("dump") end)
    R:Add(report, 0)
    UI.Tooltip(report, "Debug report", "A copyable report: characters, team, layer, modules, the last addon messages and the log.")
    local log = UI.Button(at, half, "Show log", function() ns.HandleDebugCommand("log") end)
    log:SetPoint("LEFT", report, "RIGHT", 8, 0)
    R:Space(UI.ROW + 6)
    local clear = UI.Button(at, half, "Clear log", function() ns.HandleDebugCommand("clear") end)
    R:Add(clear, 0)
    local ping = UI.Button(at, half, "Ping team", function() ns.Ping() end)
    ping:SetPoint("LEFT", clear, "RIGHT", 8, 0)
    UI.Tooltip(ping, "Ping team", "Whispers every team member with three spellings of the name and prints which one answered.")

    local hy = -(TOOLS_H + 8)
    local ht, col = Tile(d, 0, hy, PAGE_W, PANEL_H + hy, "How to Report a Problem", "Interface\\Icons\\INV_Misc_Book_09")
    col:Note(DEBUG_STEPS)
    col:Header("Commands")
    col:Add(CodeBox(ht, PAGE_W - 16, 100, DEBUG_COMMANDS), 108)
    col:Note("The report contains your character names, team, layer, modules, the last addon messages and the log. Blocked game actions are logged too and announced in chat.")

    -- Writing modules ----------------------------------------------------------------------
    local mt, mc = Tile(panels.modules, 0, 0, PAGE_W, PANEL_H, "Add a Module", "Interface\\Icons\\Trade_Engineering")
    mc:Note(MODULE_TEXT)
    local mh = PANEL_H + mc.y - 10
    mc:Add(CodeBox(mt, PAGE_W - 16, mh, MODULE_CODE), mh)

    -- Team communication ----------------------------------------------------------------------
    local ct, cc = Tile(panels.comm, 0, 0, PAGE_W, PANEL_H, "Talking to the Other Clients", "Interface\\Icons\\Ability_Warrior_BattleShout")
    cc:Note(COMM_TEXT)
    local ch = PANEL_H + cc.y - 10
    cc:Add(CodeBox(ct, PAGE_W - 16, ch, COMM_CODE), ch)

    -- Appearance (per account; sent with Profiles > Sync to team) ----------------------------------
    local lk = panels.look
    local LOOK_H = 260
    local bt, B = Tile(lk, 0, 0, TILE_W, LOOK_H, "Background", "Interface\\Icons\\INV_Misc_Ribbon_01")
    B:Cycle("Background", ns.BackgroundChoices, ns.ConfigBackground, ns.SetConfigBackground)
    B:Space(4)
    local desc = B:Note("")
    desc:SetHeight(44)
    desc:SetJustifyV("TOP")
    B:Space(22)
    local opacity = B:Slider("Artwork opacity", 10, 60, 5,
        function() return math.floor(ns.ArtAlpha() * 100 + 0.5) end,
        function(v) ns.SetArtAlpha(v / 100) end, "%d%%")
    local tint = B:Check("Artwork in the accent colour",
        ns.ArtTint, ns.SetArtTint,
        "Shows the painting in shades of MMT's accent colour instead of its own colours.")
    B:Space(4)
    local missing = B:Note("")

    local _, W = Tile(lk, X2, 0, TILE_W, LOOK_H, "Window Size", "Interface\\Icons\\INV_Misc_Spyglass_02")
    W:Slider("Settings window scale", 60, 200, 5,
        function() return math.floor(ns.ConfigScale() * 100 + 0.5) end,
        function(v) ns.SetConfigScale(v / 100) end, "%d%%")
    W:Button("Back to 100%", function() ns.SetConfigScale(1) ns.RefreshConfig() end)
    W:Space(4)
    W:Note("Also: + and - at the bottom left of this window (right-click resets), or /mmt scale <percent>. The XP window's scale is under XP Window > Fonts, Bars, Scale, Opacity.")
    W:Note("The look and size belong to this account (all its characters and profiles). Profiles > Sync to team (/mmt sync) sends them along.")

    page.OnRefresh = function()
        local key, isArt = ns.ConfigBackground(), false
        for _, b in ipairs(ns.BACKGROUNDS) do
            if b.value == key then desc:SetText(b.desc) isArt = b.art and true or false end
        end
        if key == "ART_CLASS" then
            local text, byTalents = ns.ClassArt()
            desc:SetText(("Now: %s, %s.")
                :format(text, byTalents and "from the talent points" or "the first spec (no talent points yet)"))
        end
        opacity:SetAlpha(isArt and 1 or 0.4)
        tint:SetAlpha(isArt and 1 or 0.4)
        local gone = {}
        for _, b in ipairs(ns.BACKGROUNDS) do
            if b.image and ns.ArtworkMissing(b.image) then gone[#gone + 1] = b.text end
        end
        if not ns.ArtworkCheckWorks() then
            missing:SetText("This client can't tell which artwork it has, so all of it is listed: one that stays dark isn't there.")
        else
            missing:SetText(#gone > 0 and ("Artwork this client doesn't have: " .. table.concat(gone, ", ") .. ".") or "")
        end
    end

    Show("debug")
end)
