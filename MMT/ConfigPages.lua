-- MMT: the pages of the configuration window.
-- Order of registration = order of the tabs.

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT
local PAGE_W = 698
local COL_W = 330
local COL2_X = 366

local function Opt(section, key)
    return function() return ns.db[section][key] end,
           function(v) ns.db[section][key] = v end
end

-- Status line for feedback (errors in red, success in grey).
local function StatusLine(parent)
    local fs = UI.Label(parent, "")
    fs:SetJustifyH("LEFT")
    fs.Show_ = function(text, isError)
        fs:SetText(text or "")
        if isError then fs:SetTextColor(1, 0.4, 0.4) else fs:SetTextColor(0.6, 0.6, 0.6) end
    end
    return fs
end

-- Buttons that need a second click within 3 seconds to run.
local function ConfirmButton(parent, width, text, action)
    local b
    local armed = false
    b = UI.Button(parent, width, text, function()
        if armed then
            armed = false
            b.label:SetText(text)
            action()
        else
            armed = true
            b.label:SetText("Click again")
            C_Timer.After(3, function()
                if armed then armed = false; b.label:SetText(text) end
            end)
        end
    end)
    return b
end

-- A fixed pool of list rows with mouse-wheel scrolling.
local function List(parent, width, rows, rowHeight, makeRow, fillRow)
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(width, rows * rowHeight)
    list.offset = 0
    list.rows = {}
    for i = 1, rows do
        local row = makeRow(list, i)
        row:SetSize(width, rowHeight)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
        list.rows[i] = row
    end
    -- arrows at the top / bottom edge while there is more to scroll to
    list.up = UI.ScrollArrow(list, "UP", function() list:GetScript("OnMouseWheel")(list, 1) end)
    list.up:SetPoint("BOTTOM", list, "TOP", 0, -1)
    list.down = UI.ScrollArrow(list, "DOWN", function() list:GetScript("OnMouseWheel")(list, -1) end)
    list.down:SetPoint("TOP", list, "BOTTOM", 0, 1)
    function list:Render(data)
        self.data = data
        self.offset = math.max(0, math.min(self.offset, #data - rows))
        self.up:SetShown(self.offset > 0)
        self.down:SetShown(self.offset < #data - rows)
        for i, row in ipairs(self.rows) do
            local index = i + self.offset
            if data[index] then
                fillRow(row, data[index], index)
                row:Show()
            else
                row:Hide()
            end
        end
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        self.offset = self.offset - delta
        self:Render(self.data or {})
    end)
    return list
end

local function RowBackground(row, index)
    local bg = UI.Fill(row, 1, 1, 1, (index % 2 == 0) and 0.025 or 0)
    return bg
end

-- dots to drag a list row by
local function Grip(row)
    local g = CreateFrame("Frame", nil, row)
    g:SetSize(6, 10)
    g:SetPoint("LEFT", 4, 0)
    for c = 0, 1 do
        for r = 0, 2 do
            local d = g:CreateTexture(nil, "OVERLAY")
            d:SetSize(2, 2)
            d:SetPoint("TOPLEFT", c * 4, -r * 4)
            d:SetColorTexture(1, 1, 1, 0.35)
            g[#g + 1] = d
        end
    end
    function g:Light(on) for _, t in ipairs(self) do t:SetColorTexture(1, 1, 1, on and 0.9 or 0.35) end end
    return g
end

-- drag & drop for the rows of a List (the Info window's pieces, the team):
-- onDrop(fromIndex, beforeIndex | nil = to the end); the list scrolls when the
-- cursor leaves it while dragging; a line shows where the row goes
local function DragReorder(list, visible, rowH, onDrop)
    local marker = list:CreateTexture(nil, "OVERLAY")
    marker:SetColorTexture(A[1], A[2], A[3], 1)
    marker:SetHeight(2)
    marker:Hide()
    local from, nextScroll
    local function Slot()
        local data, top = list.data, list:GetTop()
        if not data or not top or not from then return end
        local _, y = GetCursorPosition()
        local dy = top - y / list:GetEffectiveScale()
        local gap = math.max(0, math.min(visible, math.floor(dy / rowH + 0.5)))
        return math.max(1, math.min(#data + 1, list.offset + gap + 1)), dy
    end
    local function Stop()
        list:SetScript("OnUpdate", nil)
        marker:Hide()
        from = nil
    end
    for _, row in ipairs(list.rows) do
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function(self)
            if not self.index then return end
            GameTooltip:Hide()
            from, nextScroll = self.index, nil
            list:SetScript("OnUpdate", function()
                local slot, dy = Slot()
                if not slot then return end
                local now = GetTime()
                if (dy < 0 or dy > list:GetHeight()) and (not nextScroll or now >= nextScroll) then
                    nextScroll = now + 0.15
                    list:GetScript("OnMouseWheel")(list, dy < 0 and 1 or -1)
                    slot = Slot()
                end
                if slot == from or slot == from + 1 then marker:Hide() return end
                local y = -(slot - 1 - list.offset) * rowH + 1
                marker:ClearAllPoints()
                marker:SetPoint("TOPLEFT", list, "TOPLEFT", 0, y)
                marker:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, y)
                marker:Show()
            end)
        end)
        row:SetScript("OnDragStop", function()
            local f, data = from, list.data
            local slot = Slot()
            Stop()
            if not slot or slot == f or slot == f + 1 then return end
            onDrop(f, slot <= #data and slot or nil)
        end)
    end
    list:HookScript("OnHide", Stop)
end

-- shared with modules for their own settings pages
ns.ConfigHelpers = {
    PAGE_W = PAGE_W, COL_W = COL_W, COL2_X = COL2_X,
    StatusLine = StatusLine, ConfirmButton = ConfirmButton, List = List, RowBackground = RowBackground,
    Grip = Grip, DragReorder = DragReorder,
}

-- tiles: two side by side fill the page
local TILE_W, TILE_GAP = 344, 10
local TILE_IN = TILE_W - 16   -- width of the settings inside a tile

-- a framed tile with an icon and a title; returns the tile and a column inside it
local function Tile(parent, x, y, w, h, title, icon)
    local t = CreateFrame("Frame", nil, parent)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    t:SetSize(w, h)
    UI.Fill(t, A[1], A[2], A[3], 0.04)
    UI.Border(t, A[1], A[2], A[3], 0.30)
    local ic = t:CreateTexture(nil, "ARTWORK")
    ic:SetTexture(icon)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ic:SetSize(22, 22)
    ic:SetPoint("TOPLEFT", 8, -7)
    local label = UI.Label(t, title, "GameFontNormalLarge")
    label:SetPoint("LEFT", ic, "RIGHT", 8, 0)
    label:SetTextColor(A[1], A[2], A[3])
    -- a long title that doesn't fit in the large font takes the normal one
    if (label:GetStringWidth() or 0) > w - 46 and GameFontNormal then label:SetFontObject(GameFontNormal) end
    local line = t:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(A[1], A[2], A[3], 0.35)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 8, -34)
    line:SetPoint("TOPRIGHT", -8, -34)
    t.title = label
    return t, UI.Column(t, 8, -42, w - 16)
end
ns.ConfigHelpers.Tile = Tile

-- greying out settings that depend on a switch: Mark(frame) remembers what a frame holds
-- now; After(mark) returns what was added to it since (frames and texts), for UI.SetActive
local function Mark(frame)
    local seen = {}
    for _, c in ipairs({ frame:GetChildren() }) do seen[c] = true end
    for _, r in ipairs({ frame:GetRegions() }) do seen[r] = true end
    return { frame = frame, seen = seen }
end
local function After(mark)
    local out = {}
    for _, c in ipairs({ mark.frame:GetChildren() }) do if not mark.seen[c] then out[#out + 1] = c end end
    for _, r in ipairs({ mark.frame:GetRegions() }) do
        if not mark.seen[r] and r.GetObjectType and r:GetObjectType() == "FontString" then out[#out + 1] = r end
    end
    return out
end
-- greys everything in list out (or back) by isOn()
local function Depend(list, isOn)
    local on = isOn() and true or false
    for _, w in ipairs(list) do UI.SetActive(w, on) end
end
ns.ConfigHelpers.Mark, ns.ConfigHelpers.After, ns.ConfigHelpers.Depend = Mark, After, Depend

-- the grey line on top of a tiled page
local function Intro(page, text)
    local fs = UI.Label(page, text)
    fs:SetPoint("TOPLEFT", 0, 0)
    fs:SetWidth(PAGE_W)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(0.75, 0.75, 0.75)
    -- where the tiles start: below the text, also when it wraps into a second line
    local h = math.ceil(fs:GetStringHeight() or 0)
    return -math.max(22, h + 10), fs
end
ns.ConfigHelpers.Intro = Intro

-- sub pages of a page as a tab strip at y (below the intro): icons, the chosen one in the
-- accent colour and underlined. tabs = { { key, label, icon (Interface\Icons\...) }, ... };
-- returns panels[key] (frames below the strip, height to the page bottom minus reserve), Show(key)
local function TabStrip(page, y, tabs, reserve)
    local panels, buttons = {}, {}
    local function Show(key)
        for k, p in pairs(panels) do p:SetShown(k == key) end
        for k, b in pairs(buttons) do
            local on = k == key
            b.label:SetTextColor(on and A[1] or 0.7, on and A[2] or 0.7, on and A[3] or 0.7)
            b.bar:SetShown(on)
        end
        page.subTab = key
    end
    local n = #tabs
    local TAB_W = math.floor((PAGE_W - (n - 1) * 6) / n)
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, y - 26)
    line:SetPoint("TOPRIGHT", 0, y - 26)
    local panelY = y - 34
    for i, t in ipairs(tabs) do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(TAB_W, 26)
        b:SetPoint("TOPLEFT", (i - 1) * (TAB_W + 6), y)
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
        p:SetPoint("TOPLEFT", 0, panelY)
        p:SetSize(PAGE_W, 564 + panelY - (reserve or 0))
        p.mmtTab = { label = t[2], show = function() Show(t[1]) end }   -- the settings search opens it (Search.lua)
        panels[t[1]] = p
    end
    Show(tabs[1][1])
    return panels, Show, 564 + panelY - (reserve or 0)
end
ns.ConfigHelpers.TabStrip = TabStrip
-- room the Sync button takes at the bottom right of a module page
ns.ConfigHelpers.SYNC_RESERVE = 34
ns.ConfigHelpers.TILE_W, ns.ConfigHelpers.TILE_GAP = TILE_W, TILE_GAP

---------------------------------------------------------------------------
-- Team
---------------------------------------------------------------------------
ns.RegisterPage("team", "Team", function(page)
    local TOP = Intro(page, "Your team: the characters MMT works with, how their clients talk to each other and how their names are shown.")
    local ROWS, ROW_H = 8, 22
    local TEAM_H = 42 + 34 + ROWS * ROW_H + 8 + (UI.ROW + 6) + UI.ROW + 6
    local Y2 = TOP - TEAM_H - 8
    local BOTTOM_H = 564 + Y2   -- the rest of the page
    local X2 = TILE_W + TILE_GAP

    -- Team Members (full width) ------------------------------------------------
    local tt, col = Tile(page, 0, TOP, PAGE_W, TEAM_H, "Team Members", "Interface\\Icons\\Spell_Holy_PrayerOfFortitude")
    local IN = PAGE_W - 16
    -- who you are playing, on the title line
    local youHover = CreateFrame("Frame", nil, tt)
    youHover:SetSize(260, 20)
    youHover:SetPoint("TOPRIGHT", -10, -8)
    local you = UI.Label(youHover, "")
    you:SetPoint("RIGHT")
    you:SetJustifyH("RIGHT")
    you:SetTextColor(0.5, 0.5, 0.5)
    ns.HoverMember(youHover, function() return ns.PlayerFull() end)
    col:Note("In the order the Info window shows them: drag a row by its dots to move it. Green dot = online with MMT. Every account keeps its own team: add it on each client, or send it with Profiles > Sync to team (/mmt sync).")

    local list = List(tt, IN, ROWS, ROW_H, function(parent, i)
        local row = CreateFrame("Frame", nil, parent)
        RowBackground(row, i)
        row.grip = Grip(row)
        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetSize(6, 6)
        row.dot:SetPoint("LEFT", 18, 0)
        row.name = UI.Label(row, "")
        row.name:SetPoint("LEFT", 32, 0)
        row.guild = UI.Label(row, "", "GameFontNormalSmall")
        row.guild:SetPoint("LEFT", 170, 0)
        row.guild:SetWidth(170)
        row.guild:SetJustifyH("LEFT")
        row.guild:SetWordWrap(false)
        row.roles = UI.Label(row, "")
        row.roles:SetPoint("LEFT", 350, 0)
        row.roles:SetWidth(IN - 380)
        row.roles:SetJustifyH("LEFT")
        row.roles:SetWordWrap(false)
        row.roles:SetTextColor(0.55, 0.55, 0.55)
        row.remove = UI.TextButton(row, "x", function() ns.RemoveMember(row.key); ns.Refresh() end)
        row.remove:SetPoint("RIGHT", -2, 0)
        ns.HoverMember(row, function() return row.key end, function(tip, key)
            tip:AddLine("Team key: " .. key, 0.5, 0.5, 0.5)
            tip:AddLine("Drag to change the order.", 0.5, 0.5, 0.5)
        end)
        row:HookScript("OnEnter", function(self) self.grip:Light(true) end)
        row:HookScript("OnLeave", function(self) self.grip:Light(false) end)
        return row
    end, function(row, key, index)
        row.key, row.index = key, index
        local m = ns.db.team[key]
        row.name:SetText(ns.FirstName(key))
        local c = m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
        if c then row.name:SetTextColor(c.r, c.g, c.b) else row.name:SetTextColor(1, 1, 1) end
        if ns.IsOnline(key) then row.dot:SetColorTexture(0.3, 1, 0.3, 1) else row.dot:SetColorTexture(0.3, 0.3, 0.3, 1) end
        local roles = table.concat(ns.MemberRoleList(key), ", ")
        row.roles:SetText(roles ~= "" and roles or "no roles")
        -- guild compared to the leader's (FTL leader, else the character you play)
        local leader = (ns.FTLLeader and ns.FTLLeader()) or ns.PlayerFull()
        local lg, mg = ns.MemberGuild(leader), ns.MemberGuild(key)
        if key == leader or (ns.IsSelf(key) and ns.IsSelf(leader)) then
            row.guild:SetText(mg and "|cff4cff4cleader, in a guild|r" or (mg == false and "|cff999999leader, no guild|r" or ""))
        elseif mg == nil or lg == nil then
            row.guild:SetText("")   -- not known yet (offline, no heartbeat)
        elseif mg == false then
            row.guild:SetText("|cff999999no guild|r")
        elseif mg == lg then
            row.guild:SetText("|cff4cff4cin same guild as leader|r")
        else
            row.guild:SetText("|cffffd36bdifferent guild as leader|r")
        end
    end)
    col:Add(list, ROWS * ROW_H)
    -- drag a member up or down (the Info window's order)
    DragReorder(list, ROWS, ROW_H, function(from, before)
        local data = list.data
        ns.MoveMemberBefore(data[from], before and data[before] or nil)
        ns.Refresh()
    end)
    local empty = UI.Label(tt, "No team members yet. Group up and press \"Add group\", or type a name below.")
    empty:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -4)
    empty:SetTextColor(0.5, 0.5, 0.5)

    col:Space(8)
    local status
    -- one line: name field + Add, then the quick buttons on the right
    local input = UI.EditBox(tt, 220, "First Last", function(text, box)
        local ok, err = ns.AddManual(text)
        if ok then box:SetText(""); box:ClearFocus(); status.Show_("Added " .. ns.Trim(text) .. ".") else status.Show_(err, true) end
        ns.Refresh()
    end)
    col:Add(input, 0)
    local add = UI.Button(tt, 60, "Add", function() input:GetScript("OnEnterPressed")(input) end)
    add:SetPoint("LEFT", input, "RIGHT", 6, 0)
    local clear = ConfirmButton(tt, 110, "Remove all", function() ns.ClearTeam(); ns.Refresh() end)
    clear:SetPoint("TOPRIGHT", tt, "TOPLEFT", 8 + IN, col.y)
    local target = UI.Button(tt, 95, "Add target", function()
        if UnitExists("target") and UnitIsPlayer("target") then
            ns.AddUnit("target")
            status.Show_("")
        else
            status.Show_("Target a player first.", true)
        end
        ns.Refresh()
    end)
    target:SetPoint("RIGHT", clear, "LEFT", -6, 0)
    local me = UI.Button(tt, 80, "Add me", function() ns.AddUnit("player"); ns.Refresh() end)
    me:SetPoint("RIGHT", target, "LEFT", -6, 0)
    local group = UI.Button(tt, 100, "Add group", function()
        local n = ns.AddGroupMembers()
        status.Show_(n > 0 and ("Added " .. n .. " character(s) from your group.") or "Nobody new in your group.")
        ns.Refresh()
    end)
    group:SetPoint("RIGHT", me, "LEFT", -6, 0)
    UI.Tooltip(group, "Add group", "Adds you and everybody in your party or raid.")
    col:Space(UI.ROW + 6)
    -- everybody in one guild but guild comm off: recommend it (red bar on the status row)
    local banner = CreateFrame("Frame", nil, tt)
    banner:SetSize(IN, UI.ROW)
    banner:SetPoint("TOPLEFT", tt, "TOPLEFT", 8, col.y)
    UI.Fill(banner, 0.55, 0.08, 0.08, 0.85)
    banner.text = UI.Label(banner, "Your online team members are in your guild: turn on \"Use guild channel\" (Communication, below) on every client for faster, more reliable messages.", "GameFontNormalSmall")
    banner.text:SetPoint("LEFT", 8, 0)
    banner.text:SetPoint("RIGHT", -8, 0)
    banner.text:SetJustifyH("LEFT")
    banner.text:SetWordWrap(false)
    banner.text:SetTextColor(1, 0.9, 0.9)
    banner:Hide()
    status = StatusLine(tt)
    status:SetWidth(IN)
    col:Add(status, UI.ROW)
    -- a status message (added, error, ...) shows instead of the bar for a moment
    local showStatus = status.Show_
    status.Show_ = function(text, isError)
        showStatus(text, isError)
        banner:SetAlpha((text and text ~= "") and 0 or 1)
    end

    -- Communication (bottom left) ------------------------------------------------
    local _, C = Tile(page, 0, Y2, TILE_W, BOTTOM_H, "Communication", "Interface\\Icons\\Ability_Warrior_BattleShout")
    local gg, sg = Opt("comm", "guild")
    C:Check("Use guild channel", gg, function(v)
        if v and not IsInGuild() then
            ns.Print("\"Use guild channel\" needs a guild: this character isn't in one.")
            return
        end
        sg(v)
        if v and ns.ReadGuildRoster then
            ns.ReadGuildRoster()
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        end
    end, "One message on the guild channel reaches every team member in your guild, grouped or not, and the guild roster shows who is online. Team members outside the guild still get whispers. Every guild member running MMT receives the messages too (and ignores them). Turn it on on every client. Needs a guild; switched off at login when this character isn't in one. With it, /mmt sync also sends the settings of the modules when everybody is in your guild.")
    local gf, sf = Opt("comm", "fast")
    C:Check("Faster sending (1200 bytes/s)", gf, sf,
        "Increases the amount of data sent between team members for internal communication purposes by up to 50%.\nThis setting should be kept off, because it might cause the server to disconnect you if used excessively.")
    C:Space(4)
    C:Note("Addons have limits on how much data can be sent to other addons and clients. MMT tries to avoid hitting the threshold, which can make sharing the profile slow.\nFor best performance, join the same guild with all characters and enable \"Use guild channel\".")
    local commInfo = C:Note("")

    -- Privacy (bottom right) -------------------------------------------------------
    local ptile, P = Tile(page, X2, Y2, TILE_W, BOTTOM_H, "Privacy", "Interface\\Icons\\Ability_Stealth")
    -- "Hide names outside MMT too" hooks other addons' frames at load: switching
    -- it on or off only works fully after a UI reload, so it reloads right away
    local function AskReload(what, apply)
        UI.AskReload(what .. "\n\nOther addons only pick this up after a UI reload. Reload now?",
            function() ns.privacyReloading = true apply() end)
    end
    local gm, sm = Opt("privacy", "nameMode")
    local function SetMode(v)
        sm(v) ns.Fire("STATUS_CHANGED") if ns.PrivacyChanged then ns.PrivacyChanged() end
    end
    P:Cycle("Show characters by", {
        { value = "FIRST", text = "First name" },
        { value = "LAST", text = "Last name" },
        { value = "FULL", text = "Full name" },
        { value = "CLASS", text = "Class (Druid 1, Druid 2)" },
        { value = "SLOT", text = "Slot (Slot 1, Slot 2)" },
    }, gm, function(v)
        -- with hiding on, every change needs a reload: other addons' frames keep
        -- the old names until then ("Full name" switches the hiding off, and back on)
        local p = ns.db.privacy
        if p.hideOutside and v ~= p.nameMode then
            local what
            if v == "FULL" then what = "\"Full name\" switches \"Hide names outside MMT too\" off."
            elseif p.nameMode == "FULL" then what = "This switches \"Hide names outside MMT too\" on again."
            else what = "Your team's names outside MMT change to the new setting." end
            AskReload(what, function() SetMode(v) end)
            return
        end
        SetMode(v)
    end)
    local gd, sd = Opt("privacy", "debugFull")
    P:Check("Keep full names in debug logs", gd, sd,
        "Off: names in the debug log and report are replaced by the names shown above (\"Slot 1\" when that is the full name). For reports you post somewhere.")
    local gh, sh = Opt("privacy", "hideOutside")
    local hideCheck = P:Check("Hide names outside MMT too", gh, function(v)
            AskReload(v and "Hide your team's names outside MMT too." or "Show your team's real names outside MMT again.",
                function() sh(v) if ns.PrivacyChanged then ns.PrivacyChanged() end end)
        end,
        "Requires /reload: MMT will try to obfuscate the names of your team on all Blizzard and other addon frames, including chat, tooltips, player/target/group/raid etc. according to the setting made above.\nIf \"Full name\" is selected, this option automatically switches off.")
    local worldMark = Mark(ptile)
    local gw, sw = Opt("privacy", "worldNames")
    local worldDrop = P:Cycle("Name above characters", {
        { value = "NAMEPLATES", text = "Show nameplates" },
        { value = "HIDE", text = "Hide friendly player names" },
    }, function() return gw() or "NAMEPLATES" end, function(v)
        sw(v) if ns.ApplyWorldNames then ns.ApplyWorldNames() end
    end)
    UI.Tooltip(worldDrop, "Name above characters",
        "MMT can change the names everywhere, EXCEPT for the name right above the character in the 3D-world; it's protected by Blizzard.\nSelect how MMT should handle this:\n\n"
        .. "1) Show nameplates => will switch on player nameplates (native or addon) which will use MMT's privacy setting\n\n"
        .. "2) Hide friendly player names => will hide the names for ALL friendly players in the 3D world (unit frames, tooltips etc. will still show)")
    local worldDep = After(worldMark)
    P:Space(4)
    P:Note("All MMT features (core and modules) will use this setting. If \"Hide names outside MMT\" is enabled, the addon will also try to obfuscate the names there.\nMacros will still carry the full name to work, regardless of this setting.")

    page.OnRefresh = function()
        local members = ns.SortedMembers()
        list:Render(members)
        empty:SetShown(#members == 0)
        -- the members whose guild is known (online, heartbeat arrived) all in yours;
        -- offline members don't count until they are heard from
        local own = ns.OwnGuildKey and ns.OwnGuildKey()
        local sameGuild, known = own ~= nil, 0
        for _, key in ipairs(members) do
            local g = ns.MemberGuild(key)
            if g ~= nil and not ns.IsSelf(key) then
                known = known + 1
                if g ~= own then sameGuild = false end
            end
        end
        sameGuild = sameGuild and known > 0
        banner:SetShown(sameGuild and not ns.db.comm.guild)
        you:SetText("You are playing " .. ns.FirstName(ns.PlayerFull()) .. ".")
        local full = ns.db.privacy.nameMode == "FULL"
        hideCheck:SetAlpha(full and 0.4 or 1)
        if hideCheck.SetEnabled then hideCheck:SetEnabled(not full) end
        Depend(worldDep, function() return ns.db.privacy.hideOutside and not full end)
        if ns.db.comm.guild then
            if not IsInGuild() then
                commInfo:SetText("|cffff6666Not in a guild:|r messages go to the group and by whisper as usual.")
            else
                local outside = ns.TeamOutsideGuild()
                local names = {}
                for _, k in ipairs(outside) do names[#names + 1] = ns.FirstName(k) end
                commInfo:SetText(#outside == 0 and "Guild mode: every team member is reached over the guild channel."
                    or ("Not over the guild channel (party/raid or whisper): " .. table.concat(names, ", ")
                        .. ". Needs the same guild, \"Use guild channel\" on there too, and online."))
            end
        else
            commInfo:SetText("")
        end
    end
    -- heartbeats (online state, guild) update the list and the guild comm bar while the page is open
    ns.Listen("STATUS_CHANGED", ns.Coalesce(function() if page:IsVisible() then page.OnRefresh() end end, 0.5))
end)

---------------------------------------------------------------------------
-- Roles: the roles on the left, members and items of the selected one on the right
---------------------------------------------------------------------------
local LEFT_W = 236
local RIGHT_X = LEFT_W + TILE_GAP
local RIGHT_W = PAGE_W - RIGHT_X
local RIGHT_IN = RIGHT_W - 16

ns.RegisterPage("roles", "Roles", function(page)
    local TOP = Intro(page, "Roles group your characters by job (e.g. Tailor, Herbs, Cloth). Trading with a team member hands over the items of their roles (Trade / Mail / Vendor page).")
    local selected
    local quality, itemGroup = 0, "cloth"
    local FULL_H = 564 + TOP

    -- Roles (left, full height) ----------------------------------------------------
    local ROLE_ROWS = 14
    local lt, L = Tile(page, 0, TOP, LEFT_W, FULL_H, "Roles", "Interface\\Icons\\INV_Scroll_03")
    local LIN = LEFT_W - 16
    local roleList = List(lt, LIN, ROLE_ROWS, 22, function(parent, i)
        local row = CreateFrame("Button", nil, parent)
        RowBackground(row, i)
        row.sel = UI.Fill(row, A[1], A[2], A[3], 0.18, "BORDER")
        row.name = UI.Label(row, "")
        row.name:SetPoint("LEFT", 8, 0)
        row.name:SetPoint("RIGHT", -44, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.count = UI.Label(row, "")
        row.count:SetPoint("RIGHT", -26, 0)
        row.count:SetTextColor(0.5, 0.5, 0.5)
        row.remove = UI.TextButton(row, "x", function() ns.RemoveRole(row.role); ns.Refresh() end)
        row.remove:SetPoint("RIGHT", -2, 0)
        row:SetScript("OnClick", function() selected = row.role; ns.RefreshConfig() end)
        return row
    end, function(row, role)
        row.role = role
        row.name:SetText(role)
        row.count:SetText(ns.MembersWithRole(role))
        row.sel:SetShown(role == selected)
    end)
    L:Add(roleList, ROLE_ROWS * 22 + 8)

    local roleStatus
    local roleInput = UI.EditBox(lt, LIN - 50, "New role", function(text, box)
        local name, err = ns.AddRole(text)
        if name then selected = name; box:SetText(""); box:ClearFocus(); roleStatus.Show_("") else roleStatus.Show_(err, true) end
        ns.Refresh()
    end)
    L:Add(roleInput, 0)
    local roleAdd = UI.Button(lt, 44, "Add", function() roleInput:GetScript("OnEnterPressed")(roleInput) end)
    roleAdd:SetPoint("LEFT", roleInput, "RIGHT", 6, 0)
    L:Space(UI.ROW + 4)
    roleStatus = StatusLine(lt)
    roleStatus:SetWidth(LIN)
    L:Add(roleStatus, 18)
    L:Note("Click a role to edit its members and items. The number is how many characters have it.")
    L:Note("Soulbound and quest items are never traded. A trade holds 6 stacks.")

    -- Members of the role (right, top) ---------------------------------------------
    local MEM_H = 42 + 5 * 22 + 8
    local mt, R1 = Tile(page, RIGHT_X, TOP, RIGHT_W, MEM_H, "Members", "Interface\\Icons\\INV_Misc_Head_Human_01")
    local memberChecks, memberKeys = {}, {}
    local half = RIGHT_IN / 2
    for i = 1, 10 do
        local cb = UI.Check(mt, half - 8, "",
            function() return selected and memberKeys[i] and ns.HasRole(memberKeys[i], selected) end,
            function(v) if selected and memberKeys[i] then ns.SetMemberRole(memberKeys[i], selected, v) end end)
        cb:SetPoint("TOPLEFT", mt, "TOPLEFT", 8 + ((i - 1) % 2) * half, R1.y - math.floor((i - 1) / 2) * 22)
        ns.HoverMember(cb, function() return memberKeys[i] end)
        memberChecks[i] = cb
    end
    local noTeam = UI.Label(mt, "Add team members on the Team tab first.")
    noTeam:SetPoint("TOPLEFT", mt, "TOPLEFT", 8, R1.y - 2)
    noTeam:SetTextColor(0.5, 0.5, 0.5)
    local noRole = UI.Label(mt, "Create a role on the left (e.g. Cloth), then tick its members and add items.")
    noRole:SetPoint("TOPLEFT", mt, "TOPLEFT", 8, R1.y - 2)
    noRole:SetWidth(RIGHT_IN)
    noRole:SetJustifyH("LEFT")
    noRole:SetTextColor(0.5, 0.5, 0.5)

    -- Items of the role (right, below) -----------------------------------------------
    local IT_Y = TOP - MEM_H - 8
    local it, R = Tile(page, RIGHT_X, IT_Y, RIGHT_W, 564 + IT_Y, "Items", "Interface\\Icons\\INV_Crate_01")
    local ruleList = List(it, RIGHT_IN, 7, 20, function(parent, i)
        local row = CreateFrame("Frame", nil, parent)
        RowBackground(row, i)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(14, 14)
        row.icon:SetPoint("LEFT", 6, 0)
        row.text = UI.Label(row, "")
        row.text:SetPoint("LEFT", 26, 0)
        row.text:SetPoint("RIGHT", -26, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.remove = UI.TextButton(row, "x", function() ns.RemoveRule(selected, row.i); ns.Refresh() end)
        row.remove:SetPoint("RIGHT", -2, 0)
        return row
    end, function(row, rule, index)
        row.i = index
        local text, icon, r, g, b = ns.DescribeRule(rule)
        row.text:SetText(text)
        row.text:SetTextColor(r, g, b)
        row.icon:SetTexture(icon or "Interface\\Buttons\\WHITE8x8")
        if icon then row.icon:SetVertexColor(1, 1, 1) else row.icon:SetVertexColor(0.3, 0.3, 0.3) end
    end)
    R:Add(ruleList, 7 * 20 + 8)
    local noRules = UI.Label(it, "No items or rules on this role yet.")
    noRules:SetPoint("TOPLEFT", ruleList, "TOPLEFT", 6, -4)
    noRules:SetTextColor(0.5, 0.5, 0.5)

    local ruleStatus
    local function AddRule(rule)
        if not selected then ruleStatus.Show_("Select or create a role first.", true) return false end
        local ok, err = ns.AddRule(selected, rule)
        ruleStatus.Show_(ok and "" or err, not ok)
        ns.Refresh()
        return ok
    end

    local drop = UI.Button(it, RIGHT_IN, "Drop an item from your bags here", function()
        local kind, id = GetCursorInfo()
        if kind == "item" then
            AddRule({ type = "item", itemID = id, name = (ns.ItemInfo(id)) })
            ClearCursor()
        end
    end)
    drop:SetScript("OnReceiveDrag", drop:GetScript("OnClick"))
    R:Add(drop, UI.ROW + 4)

    local itemInput = UI.EditBox(it, RIGHT_IN - 52, "Click, then shift-click an item", function(text, box)
        local rule = ns.RuleFromText(text)
        if rule and AddRule(rule) then box:SetText(""); box:ClearFocus() end
    end)
    UI.AcceptItemLinks(itemInput, function(link)
        ruleStatus.Show_(link .. "  - press Enter or Add.")
    end)
    UI.Tooltip(itemInput, "Add an item", "Click into the field, then shift-click an item in your bags, the loot window, a chat link or any other window. Item IDs and exact item names work too.")
    R:Add(itemInput, 0)
    local itemAdd = UI.Button(it, 44, "Add", function() itemInput:GetScript("OnEnterPressed")(itemInput) end)
    itemAdd:SetPoint("LEFT", itemInput, "RIGHT", 8, 0)
    R:Space(UI.ROW + 4)

    local grey = UI.Button(it, half - 4, "All grey items", function() AddRule({ type = "quality", quality = 0 }) end)
    R:Add(grey, 0)
    local boe = UI.Button(it, half - 4, "All Bind on Equip", function() AddRule({ type = "boe" }) end)
    boe:SetPoint("LEFT", grey, "RIGHT", 8, 0)
    R:Space(UI.ROW + 4)

    local qualities = {}
    for q = 0, 5 do qualities[#qualities + 1] = { value = q, text = ns.QualityName(q) } end
    local qCycle = UI.Cycle(it, RIGHT_IN - 52, "Quality", qualities,
        function() return quality end, function(v) quality = v end)
    R:Add(qCycle, 0)
    local qAdd = UI.Button(it, 44, "Add", function() AddRule({ type = "quality", quality = quality }) end)
    qAdd:SetPoint("LEFT", qCycle, "RIGHT", 8, 0)
    R:Space(UI.ROW + 4)

    local groups = {}
    for _, g in ipairs(ns.ITEM_GROUPS) do
        groups[#groups + 1] = g.header and { header = true, text = g.header } or { value = g.id, text = g.name }
    end
    local cCycle = UI.Dropdown(it, RIGHT_IN - 52, "Item group", groups,
        function() return itemGroup end, function(v) itemGroup = v end)
    R:Add(cCycle, 0)
    UI.Tooltip(cCycle, "Item group", "Ready-made groups by item category, e.g. Cloth (Linen, Wool, Silk, Mageweave, Runecloth and their bolts), Herbs, Potions, Food & drink or Reagents.")
    local cAdd = UI.Button(it, 44, "Add", function() AddRule({ type = "group", group = itemGroup }) end)
    cAdd:SetPoint("LEFT", cCycle, "RIGHT", 8, 0)
    R:Space(UI.ROW + 4)

    ruleStatus = StatusLine(it)
    ruleStatus:SetWidth(RIGHT_IN)
    R:Add(ruleStatus, 16)

    local rightSide = { ruleList, drop, itemInput, itemAdd, grey, boe, qCycle, qAdd, cCycle, cAdd, ruleStatus }

    page.OnRefresh = function()
        local roles = ns.SortedRoleNames()
        if selected and not ns.db.roles[selected] then selected = nil end
        if not selected then selected = roles[1] end
        roleList:Render(roles)

        for _, region in ipairs(rightSide) do region:SetShown(selected ~= nil) end
        noRole:SetShown(selected == nil)
        mt.title:SetText(selected and ("Members of " .. selected) or "Members")
        it.title:SetText(selected and ("Items for " .. selected) or "Items")

        local rules = selected and ns.db.roles[selected].rules or {}
        ruleList:Render(rules)
        noRules:SetShown(selected ~= nil and #rules == 0)

        local members = ns.SortedMembers()
        for i, cb in ipairs(memberChecks) do
            memberKeys[i] = members[i]
            cb.label:SetText(members[i] and ns.FirstName(members[i]) or "")
            cb:SetShown(selected ~= nil and members[i] ~= nil)
            cb.Refresh()
        end
        noTeam:SetShown(selected ~= nil and #members == 0)
    end
    ns.On("GET_ITEM_INFO_RECEIVED", function()
        if page:IsVisible() then ruleList:Render(ruleList.data or {}) end
    end)
end)

---------------------------------------------------------------------------
-- Info window: a line on top, then four tiles (Basics, General Look & Feel,
-- Column Visibility & Order, Miscellaneous); fonts, bars, scale and opacity
-- in a side window
---------------------------------------------------------------------------

local xpLook
function ns.ToggleXPLook(window)
    if xpLook and xpLook:IsShown() then xpLook:Hide() return end
    if not xpLook then
        local f = CreateFrame("Frame", "MMTXPLookFrame", window)   -- scales and hides with the settings window
        f:SetFrameStrata(window:GetFrameStrata())
        f:SetFrameLevel(window:GetFrameLevel() + 50)
        f:EnableMouse(true)
        f:SetClampedToScreen(true)
        UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
        UI.Border(f, 0.22, 0.22, 0.24, 1)
        f.widgets = {}
        local title = UI.Label(f, "Info Window: fonts, bars, scale, opacity", "GameFontNormal")
        title:SetPoint("TOPLEFT", 16, -14)
        local close = UI.TextButton(f, "x", function() f:Hide() end, 20)
        close:SetPoint("TOPRIGHT", -8, -8)

        local C = UI.Column(f, 16, -40, COL_W)
        local gf, sf = Opt("xp", "font")
        C:Cycle("Font", function()
            local l = {}
            for _, font in ipairs(ns.fonts) do l[#l + 1] = { value = font.name, text = font.name } end
            local cur = ns.db.xp.font
            local known = false
            for _, c in ipairs(l) do if c.value == cur then known = true end end
            if not known then l[#l + 1] = { value = cur, text = "Custom" } end
            return l
        end, gf, sf)
        local go, so = Opt("xp", "outline")
        C:Cycle("Outline", {
            { value = "NONE", text = "None" },
            { value = "OUTLINE", text = "Thin" },
            { value = "THICKOUTLINE", text = "Thick" },
            { value = "MONOCHROME,OUTLINE", text = "Mono" },
        }, go, so)
        local gz, sz = Opt("xp", "size")
        C:Slider("Font size", 8, 24, 1, gz, sz)
        local gw, sw = Opt("xp", "width")
        C:Slider("Width", 100, 400, 5, gw, sw)
        local gh, sh = Opt("xp", "barHeight")
        C:Slider("Bar height", 10, 36, 1, gh, sh)
        local grg, srg = Opt("xp", "rowGap")
        C:Slider("Row spacing", 0, 10, 1, grg, srg)
        local gs, ss = Opt("xp", "scale")
        C:Slider("Scale", 0.5, 2, 0.05, gs, ss, "%.2f")
        local gal, sal = Opt("xp", "alpha")
        C:Slider("Window opacity", 0.2, 1, 0.05, gal, sal, "%.2f")
        local gb, sb = Opt("xp", "bgAlpha")
        C:Slider("Background opacity", 0, 1, 0.05, gb, sb, "%.2f")
        f:SetSize(COL_W + 32, -C.y + 12)
        f:SetScript("OnShow", function(self) for _, w in ipairs(self.widgets) do w.Refresh() end end)
        UI.CloseOnEscape(f)
        xpLook = f
    end
    xpLook:ClearAllPoints()
    xpLook:SetPoint("TOPLEFT", window, "TOPRIGHT", 6, 0)
    xpLook:Show()
    for _, w in ipairs(xpLook.widgets) do w.Refresh() end
end


ns.RegisterPage("xp", "Info Window", function(page)
    local TOP = Intro(page, "The Info Window is a central part of MMT that is used to show you lots of information about your team.")
    local PIECE_ROWS, PIECE_H = 9, 20   -- every piece visible without scrolling
    local EXTRA = 2 * PIECE_H           -- every tile two rows taller
    local TOP_H = 42 + 6 * UI.ROW + (UI.ROW + 2) + 8 + EXTRA   -- (8 rows now: the extra room holds the two highlight switches)
    local X2 = TILE_W + TILE_GAP
    local Y2 = TOP - TOP_H - 8
    local BOTTOM_H = 42 + 7 * PIECE_H + 6 + 2 * (UI.ROW + 2) + 8 + EXTRA

    -- Basics ----------------------------------------------------------------
    local bt, B = Tile(page, 0, TOP, TILE_W, TOP_H, "Basics", "Interface\\Icons\\INV_Misc_Gear_01")
    B:Check("Show window", Opt("xp", "enabled"))
    local basicsMark = Mark(bt)
    local glk, slk = Opt("xp", "locked")
    B:Check("Lock position", glk, slk, "Unlocked, Shift + drag or the tab above the window's corner (shown while the mouse is over the window) moves it.")
    local gct, sct = Opt("xp", "clickThrough")
    B:Check("Click-through", gct, sct, "Clicks go through the window to the game world. No mouseover details or click actions then. Otherwise: click a member to make them the FTL leader, right-click to invite, Ctrl-click to inspect, Ctrl-right-click for talents, middle-click to invite the whole team, Shift-right-click for settings.")
    B:Check("Show your own character", Opt("xp", "showSelf"))
    B:Check("Class colors", Opt("xp", "classColors"))
    B:Check("Show bars", Opt("xp", "showBars"))
    -- (the level-up and XP-gain highlights: the cogwheel of the piece "Bar value")
    local gbm, sbm = Opt("xp", "barMode")
    B:Cycle("Bars show", {
        { value = "XP", text = "Experience" },
        { value = "REP", text = "Reputation (watched faction)" },
    }, gbm, sbm)

    -- General Look & Feel ---------------------------------------------------
    local gtile, G = Tile(page, X2, TOP, TILE_W, TOP_H, "General Look & Feel", "Interface\\Icons\\INV_Misc_Ribbon_01")
    local gcs, scs = Opt("ftl", "crownSide")
    G:Cycle("Leader crown", {
        { value = "LEFT", text = "Left of the name" },
        { value = "RIGHT", text = "Right of the name" },
    }, gcs, scs)
    local ga, sa = Opt("xp", "align")
    G:Cycle("Layout", {
        { value = "SPLIT", text = "Name takes the free space" },
        { value = "LEFT", text = "Left" },
        { value = "CENTER", text = "Center" },
        { value = "RIGHT", text = "Right" },
    }, ga, sa)
    local gpa, spa = Opt("xp", "pieceAlign")
    local lineUp = G:Cycle("Column alignment behavior", {
        { value = "CENTER", text = "Centred" },
        { value = "ICONS", text = "Icons lined up" },
        { value = "LEFT", text = "Left" },
        { value = "RIGHT", text = "Right" },
        { value = "OFF", text = "Off (each row on its own)" },
    }, gpa, spa)
    UI.Tooltip(lineUp, "Column alignment behavior",
        "Each piece (durability, bags, gold, name, level, ...) gets its own column, as wide as its widest value, so it sits in the same place on every row.\n\n"
        .. "Centred / left / right: where a value sits inside its column. Icons lined up: the bag and durability icons line up on the left, the gold coins on the right.\n"
        .. "Off: every row puts its pieces side by side on its own.\n\n"
        .. "|cffaaaaaaWhen all rows show the same pieces with values of similar width, the choices look nearly the same. It shows when a row misses a piece (offline member, max level without rested XP): with columns the other pieces stay in place, with Off they move into the gap.|r")
    G:Space(4)
    local lookButton = G:Button("Fonts, Bars, Scale, Opacity", function() ns.ToggleXPLook(page:GetParent()) end)
    UI.Tooltip(lookButton, "Fonts, Bars, Scale, Opacity", "Opens a window beside this one: font, outline, font size, width, bar height, row spacing, scale, window and background opacity.")
    G:Button("Reset window position", function() ns.ResetXPPosition() end)

    -- Column Visibility & Order (left to right in the window) -----------------
    -- a piece with options (XPPieces.lua, def.options) gets a cogwheel in its row: a small
    -- popup of its settings next to the row (one at a time; Esc, x or the cogwheel close it)
    local optionPopups = {}
    local function HidePieceOptions(except)
        for id, p in pairs(optionPopups) do if id ~= except then p:Hide() end end
    end
    local function PieceOptions(owner, def)
        HidePieceOptions(def.id)
        local p = optionPopups[def.id]
        if p and p:IsShown() then p:Hide() return end
        if not p then
            p = CreateFrame("Frame", nil, UIParent)
            p:SetFrameStrata("FULLSCREEN_DIALOG")
            p:SetClampedToScreen(true)
            p:EnableMouse(true)
            p:SetWidth(240)
            p.widgets = {}   -- the widgets below register here (Refresh on every open)
            UI.Fill(p, 0.06, 0.06, 0.07, 0.97)
            UI.Border(p, A[1], A[2], A[3], 0.6)
            local title = UI.Label(p, def.title, "GameFontNormal")
            title:SetPoint("TOPLEFT", 10, -8)
            title:SetPoint("RIGHT", -26, 0)
            title:SetJustifyH("LEFT")
            title:SetWordWrap(false)
            local close = UI.TextButton(p, "x", function() p:Hide() end, 18)
            close:SetPoint("TOPRIGHT", -4, -4)
            local col = UI.Column(p, 10, -30, 220)
            for _, o in ipairs(def.options) do
                local fn = col[o[1]]
                if type(fn) == "function" then
                    local w = fn(col, select(2, unpack(o)))
                    -- a drop-down list or colour palette opened from here goes above this
                    -- popup (all of them are FULLSCREEN_DIALOG)
                    if type(w) == "table" and w.HasScript and w:HasScript("OnClick") then
                        w:HookScript("OnClick", function()
                            for _, name in ipairs({ "MMTDropdownList", "MMTColorPopup" }) do
                                local f = rawget(_G, name)
                                if f and f:IsShown() then f:SetFrameLevel(p:GetFrameLevel() + 10) end
                            end
                        end)
                    end
                end
            end
            p:SetHeight(-col.y + 8)
            UI.CloseOnEscape(p)
            optionPopups[def.id] = p
        end
        local parent, own = UIParent:GetEffectiveScale(), owner:GetEffectiveScale()
        p:SetScale((parent > 0) and own / parent or 1)
        p:SetFrameLevel(owner:GetFrameLevel() + 20)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, 0)
        for _, w in ipairs(p.widgets) do if w.Refresh then w.Refresh() end end
        p:Show()
    end
    page:HookScript("OnHide", function() HidePieceOptions() end)

    -- pieces of a row (XPPieces.lua), the name among them: drag the dots to move one, "on" / "off" shows it
    local ctile, V = Tile(page, 0, Y2, TILE_W, BOTTOM_H, "Column Visibility & Order", "Interface\\Icons\\INV_Misc_Note_01")
    local pieces
    local function Shown()
        local out = {}
        for _, e in ipairs(ns.XPPieceOrder()) do
            if ns.xpPieces[e.id] then out[#out + 1] = e end
        end
        return out
    end
    local function Redraw() pieces:Render(Shown()) end
    pieces = List(ctile, TILE_IN, PIECE_ROWS, PIECE_H, function(parent, i)
        local row = CreateFrame("Frame", nil, parent)
        RowBackground(row, i)
        row.tint = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.tint:SetAllPoints()
        row.strip = row:CreateTexture(nil, "ARTWORK")
        row.strip:SetPoint("TOPLEFT"); row.strip:SetPoint("BOTTOMLEFT")
        row.strip:SetWidth(2)
        row.grip = Grip(row)
        row.toggle = UI.TextButton(row, "", function()
            local e = row.entry
            if e and not (ns.xpPieces[e.id] and ns.xpPieces[e.id].fixed) then ns.SetXPPiece(e.id, not e.on); Redraw() end
        end, 40)
        row.toggle:SetPoint("RIGHT", -2, 0)
        UI.Tooltip(row.toggle, "On / off", "Switched-off pieces stay in the list but aren't shown. The name is always shown.")
        -- cogwheel: the piece's own settings (only pieces with options)
        row.gear = CreateFrame("Button", nil, row)
        row.gear:SetSize(14, 14)
        row.gear:SetPoint("RIGHT", row.toggle, "LEFT", -4, 0)
        row.gear.icon = row.gear:CreateTexture(nil, "ARTWORK")
        row.gear.icon:SetAllPoints()
        row.gear.icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
        row.gear.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.gear.icon:SetDesaturated(true)
        row.gear.icon:SetAlpha(0.75)
        row.gear:SetScript("OnClick", function(self)
            local d = row.entry and ns.xpPieces[row.entry.id]
            if d and d.options then PieceOptions(row, d) end
        end)
        UI.Tooltip(row.gear, "Settings", "Settings of this piece, e.g. its colour on the bar.")
        row.gear:HookScript("OnEnter", function(self) self.icon:SetDesaturated(false) self.icon:SetAlpha(1) end)
        row.gear:HookScript("OnLeave", function(self) self.icon:SetDesaturated(true) self.icon:SetAlpha(0.75) end)
        row.text = UI.Label(row, "")
        row.text:SetPoint("LEFT", row.grip, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", row.gear, "LEFT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local d = self.entry and ns.xpPieces[self.entry.id]
            self.grip:Light(true)
            if not d then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(d.title)
            if d.tip then GameTooltip:AddLine(d.tip, 1, 1, 1, true) end
            GameTooltip:AddLine("Drag to change the order (left to right in the window).", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self.grip:Light(false)
            GameTooltip:Hide()
        end)
        return row
    end, function(row, e, index)
        row.entry, row.index = e, index
        local d = ns.xpPieces[e.id]
        local on = e.on or (d and d.fixed)
        row.text:SetText(d and d.title or e.id)
        row.text:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
        local c = e.id == "name" and ns.XP_NAME_COLOUR or ns.XP_PIECE_COLOUR
        row.strip:SetColorTexture(c[1], c[2], c[3], on and 0.9 or 0.4)
        row.tint:SetColorTexture(c[1], c[2], c[3], e.id == "name" and 0.12 or 0.05)
        row.gear:SetShown(d and d.options and true or false)
        row.toggle.label:SetText((d and d.fixed) and "|cff999999always|r" or (on and "|cff55ff55on|r" or "|cff777777off|r"))
    end)
    V:Add(pieces, PIECE_ROWS * PIECE_H + 6)
    DragReorder(pieces, PIECE_ROWS, PIECE_H, function(from, before)
        local data = pieces.data
        ns.MoveXPPiece(data[from].id, nil, before and data[before].id or nil)
        Redraw()
    end)
    local resetOrder = V:Button("Restore Default Column Order", function() ns.ResetXPPieceOrder(); Redraw() end)
    UI.Tooltip(resetOrder, "Restore Default Column Order", "Durability, Free bag slots, Gold, Name, Level, Bar value, Rested XP, then the others. On / off stays as it is.")
    local arrange
    arrange = V:Button("", function() ns.ToggleXPArrange() end)
    local function ArrangeText()
        arrange.label:SetText(ns.xpArrange and "Stop drag&drop mode" or "Enable drag&drop mode for the Info window")
    end
    ArrangeText()
    UI.Tooltip(arrange, "Drag&drop mode", "Every switched-on piece, the name too, shows in the Info window with dots: drag a piece along its row, or a row up or down to change the team order. Until you click again or /reload. Also /mmt info arrange.")
    local xpDependent
    page.OnRefresh = function()
        Redraw()
        ArrangeText()
        -- the window off: every other setting greyed out
        if not xpDependent then
            xpDependent = After(basicsMark)
            for _, t in ipairs({ gtile, ctile, mtile }) do xpDependent[#xpDependent + 1] = t end
        end
        Depend(xpDependent, function() return ns.db.xp.enabled end)
    end

    -- Miscellaneous ---------------------------------------------------------
    local mtile, M = Tile(page, X2, Y2, TILE_W, BOTTOM_H, "Miscellaneous", "Interface\\Icons\\INV_Misc_Bag_08")
    -- (durability and gold format: the cogwheels of those pieces)
    M:Header("Layer hop")
    local gn, sn = Opt("xp", "layerHopNotify")
    M:Check("Notify when layer/phase switch is pending", gn, sn,
        "Shows a pulsing red \"Layer Hop\" left of the name when the game offers to move that character to another layer. Click it to accept in 3 seconds (for a teammate, their client accepts).")
    local gau, sau = Opt("xp", "layerHopAuto")
    M:Check("Accept the layer hop automatically", gau, sau, "Counts down in chat, then accepts.")
    local gd, sd = Opt("xp", "layerHopDelay")
    M:Slider("Accept after (seconds)", 1, 30, 1, gd, sd)

    M:Space(6)
    M:Note("Follow and crowd control warnings: Alerts page.")
end)

---------------------------------------------------------------------------
-- Distance window format: small side window next to the settings window
---------------------------------------------------------------------------
local distanceFormat
function ns.ToggleDistanceFormat(window, anchor)
    if distanceFormat and distanceFormat:IsShown() then distanceFormat:Hide() return end
    if not distanceFormat then
        local f = CreateFrame("Frame", "MMTDistanceFormatFrame", window)   -- scales and hides with the settings window
        f:SetFrameStrata(window:GetFrameStrata())
        f:SetFrameLevel(window:GetFrameLevel() + 50)
        f:EnableMouse(true)
        f:SetClampedToScreen(true)
        UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
        UI.Border(f, 0.22, 0.22, 0.24, 1)
        f.widgets = {}
        local title = UI.Label(f, "Distance window format", "GameFontNormal")
        title:SetPoint("TOPLEFT", 16, -14)
        local close = UI.TextButton(f, "x", function() f:Hide() end, 20)
        close:SetPoint("TOPRIGHT", -8, -8)

        local C = UI.Column(f, 16, -40, COL_W)
        local gfo, sfo = Opt("distance", "font")
        C:Cycle("Font", function()
            local l = {}
            for _, font in ipairs(ns.fonts) do l[#l + 1] = { value = font.name, text = font.name } end
            return l
        end, gfo, sfo)
        local go, so = Opt("distance", "outline")
        C:Cycle("Outline", {
            { value = "NONE", text = "None" },
            { value = "OUTLINE", text = "Thin" },
            { value = "THICKOUTLINE", text = "Thick" },
        }, go, so)
        local ga, sa = Opt("distance", "align")
        C:Cycle("Alignment", {
            { value = "LEFT", text = "Left" },
            { value = "CENTER", text = "Center" },
            { value = "RIGHT", text = "Right" },
        }, ga, sa)
        local gz, sz = Opt("distance", "size")
        C:Slider("Font size", 8, 32, 1, gz, sz)
        local gw, sw = Opt("distance", "width")
        C:Slider("Width", 40, 250, 5, gw, sw)
        local gb, sb = Opt("distance", "bgAlpha")
        C:Slider("Background opacity", 0, 1, 0.05, gb, sb, "%.2f")
        f:SetSize(COL_W + 32, -C.y + 12)
        f:SetScript("OnShow", function(self) for _, w in ipairs(self.widgets) do w.Refresh() end end)
        UI.CloseOnEscape(f)
        distanceFormat = f
    end
    distanceFormat:ClearAllPoints()
    distanceFormat:SetPoint("TOPLEFT", anchor or window, "TOPRIGHT", 6, 0)
    distanceFormat:Show()
    for _, w in ipairs(distanceFormat.widgets) do w.Refresh() end
end

---------------------------------------------------------------------------
-- Alerts: follow and crowd control
---------------------------------------------------------------------------
ns.RegisterPage("alerts", "Alerts", function(page)
    local TOP = Intro(page, "You can have MMT notify you via Info window, sound or text warnings about certain conditions and situations, to help you keeping track of your team.")
    local FULL_H = 564 + TOP
    local X2 = TILE_W + TILE_GAP
    local FOLLOW_H = 42 + UI.ROW + 5 * UI.ROW + 36 + 10

    -- Follow (top left) -------------------------------------------------------------
    local ft, L = Tile(page, 0, TOP, TILE_W, FOLLOW_H, "Follow", "Interface\\Icons\\Ability_Rogue_Sprint")
    L:Note("Warns when a team character stops following.")
    local gfc, sfc = Opt("xp", "followCheck")
    L:Check("Check /follow of team", gfc, sfc,
        "Every client reports when its character starts or stops following. A member who stops gets a red, pulsing row in the Info window. Needs MMT on every client.")
    local followMark = Mark(ft)
    local gfw, sfw = Opt("xp", "followWarn")
    L:Check("Show warning when follow breaks", gfw, sfw,
        "Raid warning \"<Name> stopped following\" on the client of the character that was followed (the one you play).")
    local gfs, sfs = Opt("xp", "followSound")
    L:Check("Play sound when follow breaks", gfs, sfs, "The raid warning sound, on the same client as the warning.")
    local gfn, sfn = Opt("xp", "followIgnoreInstance")
    L:Check("Ignore follow breaks in instances", gfn, sfn,
        "In dungeons and raids a break never counts: no red row, no warning, no sound (follow is often left on purpose there). Outside instances it works as set here.")
    local gfi, sfi = Opt("xp", "followIgnoreCombat")
    L:Check("Ignore follow breaks during combat", gfi, sfi,
        "Follow often breaks in a fight. A break in combat only counts if the character still isn't following when the time below has passed after its combat ended.")
    local gfd, sfd = Opt("xp", "followCombatDelay")
    L:Slider("Check after combat (seconds)", 1, 30, 1, gfd, sfd)

    local followDep = After(followMark)

    -- Bags and Quest Log (bottom left) ------------------------------------------------
    local BY = TOP - FOLLOW_H - 8
    _, L = Tile(page, 0, BY, TILE_W, 564 + BY, "Bags and Quest Log", "Interface\\Icons\\INV_Misc_Bag_08")
    L:Note("Warns the leader (the FTL leader; without one online, the group leader if in the team, else the first online team member) when a character runs out of room.")
    local gwb, swb = Opt("warn", "bags")
    L:Check("Bags almost full", gwb, swb, "Once when a character gets down to the free slots below, and once more when its bags are full.")
    local gwba, swba = Opt("warn", "bagsAt")
    L:Slider("At free bag slots", 0, 10, 1, gwba, swba)
    local gwq, swq = Opt("warn", "quests")
    L:Check("Quest log almost full", gwq, swq, "Once when a character has only the free quest slots below left, and once more when its quest log is full.")
    local gwqa, swqa = Opt("warn", "questsAt")
    L:Slider("At free quest slots", 0, 10, 1, gwqa, swqa)
    local gwr, swr = Opt("warn", "raidWarning")
    L:Check("Show as raid warning", gwr, swr, "Besides the chat line.")
    L:Check("Play sound", Opt("warn", "sound"))

    -- Crowd Control (right, full height) -------------------------------------------
    local ct, R = Tile(page, X2, TOP, TILE_W, FULL_H, "Crowd Control", "Interface\\Icons\\Spell_Nature_Polymorph")
    R:Note("Warns when a team character can't move: stunned, feared, incapacitated or rooted. The Info window marks the row orange with the time left.")
    local ge, se = Opt("cc", "enabled")
    R:Check("Check crowd control of team", ge, se,
        "Every client reports when its character loses control and when it is free again. Needs MMT on every client.")
    local ccMark = Mark(ct)
    local gw, sw = Opt("cc", "warn")
    R:Check("Show warning", gw, sw,
        "Raid warning \"<Name> is stunned (4 s)\" on the FTL leader's client (the character you play). With no leader known, on every client. Never for the character itself.")
    local gs, ss = Opt("cc", "sound")
    R:Check("Play sound", gs, ss, "The raid warning sound, on the same client as the warning.")
    R:Space(4)
    R:Note("Report:")
    R:Check("Stuns", Opt("cc", "stun"))
    local gf, sf = Opt("cc", "fear")
    R:Check("Fears and charms", gf, sf, "Fear, horror, charm, mind control.")
    local gi, si = Opt("cc", "incap")
    R:Check("Incapacitates", gi, si, "Polymorph, sap, sleep, gouge and similar.")
    R:Check("Roots", Opt("cc", "root"))
    local gm, sm = Opt("cc", "minDuration")
    R:Slider("Ignore shorter than (seconds)", 0, 10, 1, gm, sm)
    local ccDep = After(ccMark)
    page.OnRefresh = function()
        Depend(followDep, function() return ns.db.xp.followCheck end)
        Depend(ccDep, function() return ns.db.cc.enabled end)
    end
end)

---------------------------------------------------------------------------
-- FTL
---------------------------------------------------------------------------
ns.RegisterPage("ftl", "FTL", function(page)
    local TOP = Intro(page, "FTL is short for Focusless, Targetless, Leaderless. It allows you to create macros that will always target the character you are controlling right now; like for follow or assist.\n"
        .. "|cffff7366Important: this feature originates from the software ISBoxer, but is inferior to it. The FTL target in MMT CANNOT be changed during combat.|r")
    local FULL_H = 564 + TOP

    -- Settings (left) ----------------------------------------------------------------
    local st, L = Tile(page, 0, TOP, TILE_W, FULL_H, "Settings", "Interface\\Icons\\INV_Misc_Gear_01")
    L:Check("Use FTL macros", Opt("ftl", "enabled"))
    local ftlMark = Mark(st)
    local gd, sd = Opt("ftl", "detect")
    L:Cycle("Leader", {
        { value = "MANUAL", text = "Only by click, key, command" },
        { value = "MOVE", text = "Automatic, when you move" },
    }, gd, sd)
    local gn, sn = Opt("ftl", "nameFormat")
    L:Cycle("{FTL} becomes", {
        { value = "FULL", text = "First Last" },
        { value = "FIRST", text = "First name" },
        { value = "UNIT", text = "Group unit (party2)" },
    }, gn, sn)
    local gs, ss = Opt("ftl", "skipSelf")
    L:Check("Leave {FTL} lines out on the leader", gs, ss,
        "On the leader's own client, macro lines with {FTL} are left out (the leader can't follow or assist itself).")
    local gc, sc = Opt("ftl", "crown")
    L:Check("Crown on the leader in the Info window", gc, sc)
    local ga, sa = Opt("ftl", "announce")
    L:Check("Chat line when the leader changes", ga, sa)

    L:Header("Follow-Train")
    local trainKey = UI.KeyBind(st, 160, "MMT_FOLLOW_TRAIN")
    trainKey:SetPoint("TOPLEFT", st, "TOPLEFT", 8 + 150, L.y)
    local trainLabel = UI.Label(st, "Create a Follow-Train")
    trainLabel:SetPoint("TOPLEFT", st, "TOPLEFT", 8, L.y - 4)
    UI.Tooltip(trainKey, "Create a Follow-Train", "Pressing this keybinding will have the characters follow each other in a line in the order of the team list, starting with the character you pressed the keybinding on.\n\nClick, then press the key; right-click clears it. The key must reach every window (key broadcasting): WoW lets a character start following only on a key press on its own client. With key broadcasting the train starts at the FTL leader (the character you play).")
    L:Space(UI.ROW + 2)

    L:Header("Changing the leader")
    L:Note("- Click the character in the Info window\n- Key binding \"Make this character the leader\" (Esc > Options > Keybindings > MMT (Manage My Team))\n- /mmt leader (this character) or /mmt leader <name>\n- Automatically when you move a character on its own (setting above). Not when several team characters start moving at once (movement keys or Interact with Target broadcast to every window: the leader stays), and not while following, feared or charmed.")
    local current = L:Note("")
    L:Header("Sending the macros to the team")
    L:Note("Same account and profile: nothing to do. Other accounts: log them in, then click "
        .. "Profiles > Sync to team (or /mmt sync) here and accept on each client. This sends all core "
        .. "settings, not only the macros. Put the macros on each character's bar once (Drag to bar).")

    -- right: the macros ---------------------------------------------------
    local mt, R = Tile(page, TILE_W + TILE_GAP, TOP, TILE_W, FULL_H, "Macros", "Interface\\Icons\\INV_Misc_QuestionMark")
    local selected = 1
    local status
    local nameBox, bodyBox, preview
    local function Macros() return ns.db.ftl.macros end

    local list = List(mt, TILE_IN, 5, 22, function(parent, i)
        local row = CreateFrame("Button", nil, parent)
        RowBackground(row, i)
        row.text = UI.Label(row, "")
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.sel = UI.Fill(row, A[1], A[2], A[3], 0.15, "BORDER")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
        row:SetScript("OnClick", function()
            selected = row.index
            nameBox:ClearFocus(); bodyBox.edit:ClearFocus()
            page.OnRefresh()
        end)
        return row
    end, function(row, m, index)
        row.index = index
        row.text:SetText(m.name ~= "" and m.name or "(no name)")
        row.sel:SetShown(index == selected)
    end)
    R:Add(list, 5 * 22 + 6)

    nameBox = UI.EditBox(mt, TILE_IN, "Macro name (max. 16 characters)")
    nameBox:SetMaxLetters(16)
    R:Add(nameBox, UI.ROW + 4)
    bodyBox = UI.TextArea(mt, TILE_IN, 92)
    bodyBox.edit:SetMaxLetters(255)
    R:Add(bodyBox, 98)
    bodyBox.edit:HookScript("OnTextChanged", function(self)
        local text, cut = ns.FTLResolve(self:GetText())
        preview:SetText("Here: " .. (text ~= "" and text:gsub("\n", " | ") or "(nothing: every line has {FTL})") .. (cut and "  |cffff6666(too long)|r" or ""))
    end)
    preview = R:Note("")

    local function Save()
        local name = ns.Trim(nameBox:GetText())
        local body = bodyBox.edit:GetText()
        if name == "" then status.Show_("Give the macro a name.", true) return end
        for i, m in ipairs(Macros()) do
            if i ~= selected and m.name == name then status.Show_("There is already a macro called " .. name .. ".", true) return end
        end
        local m = Macros()[selected]
        if not m then m = {}; table.insert(Macros(), m); selected = #Macros() end
        m.name, m.body = name, body
        local r = ns.FTLUpdateMacros("edit")
        status.Show_(r == "combat" and "Saved. The WoW macro is written after combat." or ("Saved: " .. name .. "."))
        page.OnRefresh()
    end

    local save = UI.Button(mt, 120, "Save", Save)
    R:Add(save, 0)
    local new = UI.Button(mt, 120, "New", function()
        table.insert(Macros(), { name = "FTL " .. (#Macros() + 1), body = "/follow {FTL}" })
        selected = #Macros()
        page.OnRefresh()
        nameBox:SetFocus(); nameBox:HighlightText()
        status.Show_("New macro: change name and text, then Save.")
    end)
    new:SetPoint("LEFT", save, "RIGHT", 8, 0)
    R:Space(UI.ROW + 4)
    local delete = ConfirmButton(mt, 120, "Delete", function()
        local m = Macros()[selected]
        if not m then return end
        table.remove(Macros(), selected)
        selected = math.max(1, selected - 1)
        ns.FTLUpdateMacros("delete")
        status.Show_("Deleted " .. m.name .. " (and its WoW macro).")
        page.OnRefresh()
    end)
    R:Add(delete, 0)
    local pickup = UI.Button(mt, 120, "Drag to bar", function()
        local m = Macros()[selected]
        if m then ns.FTLPickup(m.name) end
    end)
    UI.Tooltip(pickup, "Drag to bar", "Puts the macro on your cursor: click an action bar slot to place it. The macro is also in the game's macro window (account macros).")
    pickup:SetPoint("LEFT", delete, "RIGHT", 8, 0)
    R:Space(UI.ROW + 4)
    status = StatusLine(mt)
    status:SetWidth(TILE_IN)
    R:Add(status, UI.ROW)
    R:Note("Write {FTL} where the leader's name goes. Every client keeps these macros up to date.")

    local ftlDep
    page.OnRefresh = function()
        if not ftlDep then ftlDep = After(ftlMark) ftlDep[#ftlDep + 1] = mt end
        Depend(ftlDep, function() return ns.db.ftl.enabled end)
        local macros = Macros()
        if selected > #macros then selected = math.max(1, #macros) end
        list:Render(macros)
        local m = macros[selected]
        if not nameBox:HasFocus() then nameBox:SetText(m and m.name or "") nameBox:UpdatePlaceholder() end
        if not bodyBox.edit:HasFocus() then bodyBox.edit:SetText(m and m.body or "") end
        local leader = ns.FTLLeader()
        current:SetText("Leader now: " .. (leader and (ns.FullDisplay(leader) .. (ns.IsSelf(leader) and " (this character)" or "")) or "nobody yet"))
    end
    ns.Listen("FTL_LEADER", function() if page:IsVisible() then page.OnRefresh() end end)
end)

---------------------------------------------------------------------------
-- Automations (formerly OMT)
---------------------------------------------------------------------------
-- Automations > Miscellaneous: camera and distance window in a side window
local autoMisc
function ns.ToggleAutomationsMisc(window)
    if autoMisc and autoMisc:IsShown() then autoMisc:Hide() return end
    if not autoMisc then
        local f = CreateFrame("Frame", "MMTAutomationsMiscFrame", window)   -- scales and hides with the settings window
        f:SetFrameStrata(window:GetFrameStrata())
        f:SetFrameLevel(window:GetFrameLevel() + 50)
        f:EnableMouse(true)
        f:SetClampedToScreen(true)
        UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
        UI.Border(f, 0.22, 0.22, 0.24, 1)
        f.widgets = {}
        local title = UI.Label(f, "Automations: miscellaneous", "GameFontNormal")
        title:SetPoint("TOPLEFT", 16, -14)
        local close = UI.TextButton(f, "x", function() f:Hide() end, 20)
        close:SetPoint("TOPRIGHT", -8, -8)

        local C = UI.Column(f, 16, -34, COL_W)
        C:Header("Camera")
        C:Check("Maximum camera distance", Opt("camera", "enabled"))
        local gf, sf = Opt("camera", "factor")
        C:Slider("Zoom factor", 1, 2.6, 0.1, gf, sf, "%.1f")

        C:Header("Distance window")
        local gde, sde = Opt("distance", "enabled")
        C:Check("Show window", gde, sde,
            "Shows a small window with distance information to your target. Mostly useful for hunters that want to avoid their deadzone.")
        C:Check("Lock (click-through)", Opt("distance", "locked"))
        local gh, sh = Opt("distance", "hideNoTarget")
        C:Check("Hide without target", gh, sh, "Only applies while the window is locked.")
        local gc, sc = Opt("distance", "colorize")
        C:Check("Colour by distance", gc, sc, "Green melee, yellow up to 30, orange up to 40, red beyond.")
        C:Button("Format window", function() ns.ToggleDistanceFormat(window, f) end)
        C:Button("Reset window position", function() ns.ResetDistancePosition() end)
        f:SetSize(COL_W + 32, -C.y + 12)
        f:SetScript("OnShow", function(self) for _, w in ipairs(self.widgets) do w.Refresh() end end)
        UI.CloseOnEscape(f)
        autoMisc = f
    end
    autoMisc:ClearAllPoints()
    autoMisc:SetPoint("TOPLEFT", window, "TOPRIGHT", 6, 0)
    autoMisc:Show()
    for _, w in ipairs(autoMisc.widgets) do w.Refresh() end
end

ns.RegisterPage("automations", "Automations", function(page)
    local TOP = Intro(page, "Features to get away from puny hoomanz faster!")
    local X2 = TILE_W + TILE_GAP

    -- NPC Interactions (top left) -------------------------------------------------------
    local NPC_H = 42 + 5 * UI.ROW + 4 + 40
    local _, L = Tile(page, 0, TOP, TILE_W, NPC_H, "NPC Interactions", "Interface\\GossipFrame\\GossipGossipIcon")
    local gv, sv = Opt("gossip", "vendor")
    L:Check("Go straight to the vendor", gv, sv,
        "Opens the vendor pane even when the NPC has other options, e.g. an innkeeper.")
    local gtx, stx = Opt("gossip", "taxi")
    L:Check("Go straight to the flight map", gtx, stx,
        "At a flight master, picks \"I need a ride\" so the flight map opens at once. With \"Take flight paths with the team\" the team members then follow you without clicking.")
    local gbk, sbk = Opt("gossip", "bank")
    L:Check("Go straight to the bank", gbk, sbk,
        "At a banker, picks \"I would like to check my deposit box\" so the bank opens at once.")
    local gdl, sdl = Opt("gossip", "dialog")
    L:Check("Click through NPC dialogs", gdl, sdl,
        "When an NPC has no quests and only plain dialog lines, MMT picks them one after another to advance the conversation. Lines that could cost gold, teleport, train, bind your hearthstone or start a fight are left to you, and NPCs with any other option (vendor, trainer, flights, ...) stay manual.")
    L:Check("Hold Shift to skip automation",
        function() return ns.db.shiftBypass end,
        function(v) ns.db.shiftBypass = v end,
        "Hold Shift while an NPC window opens to keep that page manual. Pick an option without Shift and the next page is automated again.")
    L:Space(4)
    L:Note("If you are looking for Quest related automations and tracking, see the Quest Tracker-module.")

    -- Socializing (bottom left) ------------------------------------------------------------
    local SY = TOP - NPC_H - 8
    local st, S = Tile(page, 0, SY, TILE_W, 564 + SY, "Socializing", "Interface\\Icons\\Spell_Holy_Resurrection")
    S:Header("Group invites")
    S:Check("Accept from team members", Opt("invites", "team"))
    S:Check("Accept from friends", Opt("invites", "friends"))
    S:Check("Accept from Battle.net friends", Opt("invites", "bnet"))
    S:Check("Accept from guild members", Opt("invites", "guild"))
    local gw, sw = Opt("invites", "whisper")
    S:Check("Invite people who whisper the keyword", gw, sw,
        "Anyone who whispers you exactly this word (not case-sensitive) gets a group invite.")
    -- keyword: saved on Enter or when the box loses focus
    local keyword = UI.EditBox(st, TILE_IN - 24, "keyword", function(text, box)
        local word = ns.Trim(text)
        if word ~= "" then ns.db.invites.keyword = word end
        box:SetText(ns.db.invites.keyword)
        box:ClearFocus()
    end)
    keyword:HookScript("OnEditFocusLost", function(box)
        local word = ns.Trim(box:GetText())
        if word ~= "" then ns.db.invites.keyword = word end
        box:SetText(ns.db.invites.keyword)
        box:UpdatePlaceholder()
    end)
    keyword.Refresh = function()
        if not keyword:HasFocus() then keyword:SetText(ns.db.invites.keyword or "") keyword:UpdatePlaceholder() end
    end
    table.insert(page.widgets, keyword)
    S:Add(keyword, UI.ROW + 2, 24)

    S:Header("Accept automatically")
    -- sources x (resurrections, summons): any combination
    local gridY = S.y
    local resLabel = UI.Label(st, "Resurrections")
    resLabel:SetPoint("TOPLEFT", st, "TOPLEFT", 8 + 110, gridY)
    resLabel:SetTextColor(0.6, 0.6, 0.6)
    local sumLabel = UI.Label(st, "Summons")
    sumLabel:SetPoint("TOPLEFT", st, "TOPLEFT", 8 + 196, gridY)
    sumLabel:SetTextColor(0.6, 0.6, 0.6)
    S:Space(16)
    local SOURCES = { { "team", "From team" }, { "friends", "From friends" }, { "guild", "From guild" }, { "anyone", "From anyone" } }
    for _, src in ipairs(SOURCES) do
        local key, text = src[1], src[2]
        local label = UI.Label(st, text)
        label:SetPoint("TOPLEFT", st, "TOPLEFT", 8, S.y - 4)
        local res = UI.Check(st, 24, "", function() return ns.db.death.acceptRes[key] end,
            function(v) ns.db.death.acceptRes[key] = v end,
            "Accept resurrections " .. text:lower() .. ".")
        res:SetPoint("TOPLEFT", st, "TOPLEFT", 8 + 126, S.y)
        local sum = UI.Check(st, 24, "", function() return ns.db.death.acceptSummon[key] end,
            function(v) ns.db.death.acceptSummon[key] = v end,
            "Accept warlock summons " .. text:lower() .. ".")
        sum:SetPoint("TOPLEFT", st, "TOPLEFT", 8 + 204, S.y)
        S:Space(UI.ROW)
    end

    -- Group-wide Interactions (right, taller: no tile below it) --------------------------------
    local GROUP_H = 42 + 3 * 28 + 8 * UI.ROW + (UI.ROW + 2) + 36 + 12
    local _, R = Tile(page, X2, TOP, TILE_W, GROUP_H, "Group-wide Interactions", "Interface\\Icons\\Ability_Mount_RidingHorse")
    R:Header("Flight paths")
    local gt, stt = Opt("taxi", "enabled")
    R:Check("Take flight paths with the team", gt, stt,
        "When a team member picks a destination at a flight master, every team member that is talking to a flight master too (flight map open, or opened within 5 seconds) flies to the same destination. Needs MMT on every client.")
    R:Check("Print to chat", Opt("taxi", "report"))
    local gtl, stl = Opt("taxi", "tellLeader")
    R:Check("Tell the leader", gtl, stl, "Every team member answers the one who picked the flight: its chat says who took the flight too, and who couldn't and why (flight path not known, can't be reached, not at a flight master, in combat, already flying).")
    R:Slider("Delay before following (s)", 1, 5, 1, function() return ns.db.taxi.delay or 1 end, function(v) ns.db.taxi.delay = v end)
    local gtr, str = Opt("taxi", "train")
    R:Check("Enable Flight-Train", gtr, str,
        "Enabling this option will have the team take the same flight as the leader, one by one, forming a \"line\" after the specified delay.")

    R:Header("Mounts")
    local gmo, smo = Opt("mount", "mount")
    R:Check("Mount up with the leader", gmo, smo,
        "When the leader (the FTL leader; without one online, the group leader if in the team, else the first online team member) mounts, every team member nearby mounts too: the same mount if it has it, else one of the same kind, else a random favourite. Hold Shift while mounting to ride alone.")
    local gdm, sdm = Opt("mount", "dismount")
    R:Check("Dismount with the leader", gdm, sdm,
        "When the leader dismounts, every team member dismounts too, never in the air. Hold Shift while dismounting to do it alone.")
    local chosen = R:Cycle("Chosen mount (key)", function()
        local l = { { value = 0, text = "Random favourite" } }
        for _, m in ipairs(ns.MountChoices()) do l[#l + 1] = { value = m.id, text = m.name } end
        return l
    end, function() return ns.db.mount.chosen or 0 end, function(v) ns.db.mount.chosen = v end)
    UI.Tooltip(chosen, "Chosen mount (key)", "The mount of the key binding \"Mount team: chosen mount\" (Key Bindings > MMT). Pressed on the leader, it summons this mount and the team follows; where it can't be used, a random favourite. The keys \"Mount team: random favourite\" and \"Dismount team\" are there too. They work even with the two options above off; pressed while mounted, the mount keys dismount the team.")

    R:Header("When you die")
    local grl, srl = Opt("death", "release")
    R:Check("Release as team", grl, srl,
        "When a character dies, a \"Release as team\" button appears under the game's death dialog on every dead character. Clicking it releases every dead team member. It lists who is dead or a ghost.")
    local grv, srv = Opt("death", "revive")
    R:Check("Revive as team", grv, srv,
        "When a ghost reaches its corpse, a \"Revive as team\" button appears under the game's dialog. Clicking it revives every ghost that is at its corpse; one whose corpse still has a delay revives when it ends; one that isn't at its corpse says so. The list shows who can revive now.")

    -- below it, where a fourth tile would go: a pointer to the other pages and the side window
    local O = UI.Column(page, X2 + 8, TOP - GROUP_H - 14, TILE_IN)
    O:Note("For automations around trading/vendoring, Looting or Quests, see the respective section in the left navigation.")
    O:Space(4)
    local misc = O:Button("Miscellaneous", function() ns.ToggleAutomationsMisc(page:GetParent()) end)
    UI.Tooltip(misc, "Miscellaneous", "Opens a window beside this one: maximum camera distance and the distance window.")
end)

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Trade / Mail / Vendor
---------------------------------------------------------------------------
-- dropdown values: "none" plus every role
local function RoleChoices()
    local l = { { value = "", text = "None" } }
    local names = {}
    for name in pairs(ns.db.roles) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do l[#l + 1] = { value = name, text = name } end
    return l
end

-- after a reset or a new empty profile: modules back to their defaults too?
-- show(msg) reports the result (default: chat)
function ns.AskResetModules(done, show)
    show = show or function(msg) ns.Print("%s", msg) end
    UI.Confirm(done .. "\n\nAlso switch the modules back to their default (on or off)?", "Reset modules", function()
        local changed, reload = ns.ResetModuleStates()
        if changed == 0 then show(done .. " Modules were already at their defaults.")
        else show(("%s %d %s switched%s."):format(done, changed, changed == 1 and "module" or "modules",
            reload and "; reload the UI to load the ones switched on" or "")) end
        ns.Refresh()
    end, "Keep modules")
end

local function MemberChoices()
    local l = { { value = "", text = "Nobody" } }
    for _, key in ipairs(ns.SortedMembers()) do l[#l + 1] = { value = key, text = ns.ShownName(key) } end
    return l
end

-- Buy list: add / edit one entry (item, quantity, characters) in a window beside the settings
local buyEditor
function ns.OpenBuyEditor(window, index, onSave)
    local f = buyEditor
    if not f then
        f = CreateFrame("Frame", "MMTBuyEditorFrame", window)   -- scales and hides with the settings window
        f:SetFrameStrata(window:GetFrameStrata())
        f:SetFrameLevel(window:GetFrameLevel() + 50)
        f:EnableMouse(true)
        f:SetClampedToScreen(true)
        UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
        UI.Border(f, 0.22, 0.22, 0.24, 1)
        f.widgets = {}
        f.title = UI.Label(f, "", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", 16, -14)
        local close = UI.TextButton(f, "x", function() f:Hide() end, 20)
        close:SetPoint("TOPRIGHT", -8, -8)
        local W = COL_W
        local C = UI.Column(f, 16, -40, W)

        -- the item: drop it on the button, or shift-click / type it into the field
        f.itemLabel = UI.Label(f, "")
        f.itemLabel:SetWidth(W)
        f.itemLabel:SetJustifyH("LEFT")
        f.itemLabel:SetWordWrap(false)
        C:Add(f.itemLabel, 20)
        local function SetItem(id, name)
            f.itemID, f.itemName = id, name or (id and ns.ItemInfo(id)) or (id and ("item " .. id))
            f.itemLabel:SetText(f.itemID and ("Item: |cffffffff" .. f.itemName .. "|r") or "|cff999999Item: none yet|r")
        end
        f.SetItem = SetItem
        local drop = UI.Button(f, W, "Drop an item from your bags here", function()
            local kind, id = GetCursorInfo()
            if kind == "item" then SetItem(id) ClearCursor() end
        end)
        drop:SetScript("OnReceiveDrag", drop:GetScript("OnClick"))
        C:Add(drop, UI.ROW + 4)
        f.itemBox = UI.EditBox(f, W, "or click here, then shift-click an item", function(text, box)
            local rule = ns.RuleFromText(text)
            if rule and rule.itemID then SetItem(rule.itemID, rule.name) box:SetText("") box:ClearFocus()
            else f.status.Show_("Item not known: use an item link or its ID.", true) end
        end)
        UI.AcceptItemLinks(f.itemBox, function(link, box)
            local id = tonumber(link:match("item:(%d+)"))
            if id then SetItem(id, link:match("%[(.-)%]")) box:SetText("") end
        end)
        UI.Tooltip(f.itemBox, "Item", "Click into the field, then shift-click an item (bags, vendor, chat link) or type its ID and press Enter.")
        C:Add(f.itemBox, UI.ROW + 6)

        -- quantity
        local qLabel = UI.Label(f, "Quantity to carry")
        C:Add(qLabel, 0, 0)
        f.countBox = UI.EditBox(f, 60, "20")
        f.countBox:SetNumeric(true)
        f.countBox:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + W - 60, C.y + 4)
        C:Space(UI.ROW + 6)

        -- characters
        C:Header("Characters")
        f.all = UI.Check(f, W, "Every character (also ones added later)",
            function() return f.allChars end,
            function(v) f.allChars = v and true or false; f.Layout() end)
        C:Add(f.all, UI.ROW)
        f.checks, f.keys = {}, {}
        local half = W / 2
        local top = C.y
        for i = 1, 10 do
            local cb = UI.Check(f, half - 8, "",
                function() return f.keys[i] and f.chosen[f.keys[i]] end,
                function(v) if f.keys[i] then f.chosen[f.keys[i]] = v or nil end end)
            cb:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + ((i - 1) % 2) * half, top - math.floor((i - 1) / 2) * 22)
            ns.HoverMember(cb, function() return f.keys[i] end)
            f.checks[i] = cb
        end
        C:Space(5 * 22 + 6)

        f.status = StatusLine(f)
        f.status:SetWidth(W)
        C:Add(f.status, UI.ROW)
        local save = UI.Button(f, 120, "Save", function() f.Save() end)
        C:Add(save, 0)
        local cancel = UI.Button(f, 120, "Cancel", function() f:Hide() end)
        cancel:SetPoint("LEFT", save, "RIGHT", 8, 0)
        C:Space(UI.ROW + 4)
        f:SetSize(W + 32, -C.y + 10)

        f.Layout = function()
            local members = ns.SortedMembers()
            for i, cb in ipairs(f.checks) do
                f.keys[i] = members[i]
                cb.label:SetText(members[i] and ns.ShownName(members[i]) or "")
                cb:SetShown(members[i] ~= nil)
                cb:SetAlpha(f.allChars and 0.4 or 1)
                if cb.SetEnabled then cb:SetEnabled(not f.allChars) end
                cb.Refresh()
            end
            f.all.Refresh()
        end
        f.Save = function()
            local list = ns.db.merchant.buyList
            if not f.itemID then
                local rule = ns.RuleFromText(f.itemBox:GetText())
                if rule and rule.itemID then SetItem(rule.itemID, rule.name) end
            end
            if not f.itemID then f.status.Show_("Pick an item first.", true) return end
            local n = tonumber(f.countBox:GetText()) or 0
            if n <= 0 then f.status.Show_("Enter how many to carry.", true) return end
            local chars
            if not f.allChars then
                chars = {}
                for _, key in ipairs(ns.SortedMembers()) do if f.chosen[key] then chars[#chars + 1] = key end end
                -- chosen characters no longer in the team stay chosen
                for key in pairs(f.chosen) do
                    local found = false
                    for _, k in ipairs(chars) do if k == key then found = true end end
                    if not found then chars[#chars + 1] = key end
                end
                if #chars == 0 then f.status.Show_("Choose at least one character, or \"Every character\".", true) return end
            end
            -- the same item twice: the existing entry is replaced
            local at = f.index
            for i, e in ipairs(list) do
                if e.itemID == f.itemID and i ~= f.index then
                    local j = i
                    if f.index then table.remove(list, f.index) if j > f.index then j = j - 1 end end
                    at = j
                    break
                end
            end
            local entry = { itemID = f.itemID, name = f.itemName, count = n, chars = chars }
            if at then list[at] = entry else list[#list + 1] = entry; at = #list end
            f:Hide()
            if f.onSave then f.onSave(at) end
        end
        f:SetScript("OnShow", function(self) for _, w in ipairs(self.widgets) do w.Refresh() end end)
        UI.CloseOnEscape(f)
        buyEditor = f
    end

    ns.db.merchant.buyList = ns.db.merchant.buyList or {}
    local entry = index and ns.db.merchant.buyList[index]
    f.index, f.onSave = entry and index or nil, onSave
    f.title:SetText(entry and "Buy list: edit item" or "Buy list: add item")
    f.chosen = {}
    f.SetItem(entry and entry.itemID, entry and entry.name)
    f.itemBox:SetText("") f.itemBox:UpdatePlaceholder()
    f.countBox:SetText(tostring(entry and entry.count or 20))
    local chars = entry and ns.BuyEntryChars(entry)
    f.allChars = entry ~= nil and chars == nil
    if chars then for _, k in ipairs(chars) do f.chosen[k] = true end end
    local own = not entry and ns.Resolve(ns.PlayerFull())
    if own then f.chosen[own] = true end
    f.status.Show_("")
    f.Layout()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", window, "TOPRIGHT", 6, 0)
    f:Show()
end

-- Exclusion List: items MMT never trades or mails, whatever role wants them
-- (ns.db.exclusions; ns.ExcludedItem in Team.lua). A side window like the buy
-- editor: drop an item, then tick "in Trade" / "in Mail" per item.
-- The same list holds the items the team never loots (entry.loot: Loot
-- Distribution leaves them on the corpse), shown in their own view:
--   view "trade" (Trade / Mail / Vendor page): in Trade, in Mail; items that
--     are only "never loot" are not listed
--   view "loot" (Loot Distribution's Never Loot tab): the never-loot items,
--     added as loot only; "Show Trade / Mail too" (ns.db.exclusionAllColumns)
--     lists every item with all three ticks
-- The x takes the item off that view only (gone when nothing is left ticked).
local exclusionWin
function ns.OpenExclusionList(window, view)
    local f = exclusionWin
    local W, ROWS, ROW_H = 460, 12, 22
    local COL_TRADE, COL_MAIL, COL_LOOT = W - 192, W - 128, W - 64
    if not f then
        f = CreateFrame("Frame", "MMTExclusionListFrame", window)   -- scales and hides with the settings window
        f:SetFrameStrata(window:GetFrameStrata())
        f:SetFrameLevel(window:GetFrameLevel() + 50)
        f:EnableMouse(true)
        f:SetClampedToScreen(true)
        UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
        UI.Border(f, 0.22, 0.22, 0.24, 1)
        f.title = UI.Label(f, "Exclusion List", "GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT", 16, -12)
        f.title:SetTextColor(A[1], A[2], A[3])
        local close = UI.TextButton(f, "x", function() f:Hide() end, 20)
        close:SetPoint("TOPRIGHT", -8, -8)
        local C = UI.Column(f, 16, -40, W)
        f.intro = UI.Label(f, "")
        f.intro:SetWidth(W) f.intro:SetJustifyH("LEFT") f.intro:SetTextColor(0.8, 0.8, 0.8)
        C:Add(f.intro, 32)
        f.status = StatusLine(f)
        f.status:SetWidth(W)
        local function List() ns.db.exclusions = ns.db.exclusions or {} return ns.db.exclusions end
        local function LootView() return f.view == "loot" end
        local function AllColumns() return LootView() and ns.db.exclusionAllColumns and true or false end
        -- the ticks this view adds / takes away
        local function Mine() return LootView() and { loot = true } or { trade = true, mail = true } end
        local function Listed(e)
            if LootView() then return AllColumns() or e.loot == true end
            return not (e.loot and not e.trade and not e.mail)
        end
        local function Shown()
            local t = {}
            for _, e in ipairs(List()) do if Listed(e) then t[#t + 1] = e end end
            return t
        end
        f.Shown = Shown
        local function AddItem(id, name)
            if not id then return end
            local text = name or ns.ItemInfo(id) or ("item " .. id)
            for _, e in ipairs(List()) do
                if e.itemID == id then
                    if Listed(e) then f.status.Show_(text .. " is on the list already.") return end
                    for k in pairs(Mine()) do e[k] = true end   -- listed for the other view: ticked for this one too
                    f.status.Show_("") f.Layout() ns.Refresh()
                    return
                end
            end
            local entry = { itemID = id, name = text }
            for k in pairs(Mine()) do entry[k] = true end
            table.insert(List(), entry)
            f.status.Show_("")
            f.offset = math.max(0, #Shown() - ROWS)
            f.Layout() ns.Refresh()
        end
        f.AddItem = AddItem
        local drop = UI.Button(f, W, "Drop an item from your bags here", function()
            local kind, id, link = GetCursorInfo()
            if kind == "item" then AddItem(id, link and link:match("%[(.-)%]")) ClearCursor() end
        end)
        drop:SetScript("OnReceiveDrag", drop:GetScript("OnClick"))
        UI.Tooltip(drop, "Add an item", "Pick up an item in your bags and drop it on this button (or click it while holding the item). Shift-click an item into the field below works too.")
        C:Add(drop, UI.ROW + 4)
        local box = UI.EditBox(f, W, "or click here, then shift-click an item", function(text, b)
            local rule = ns.RuleFromText(text)
            if rule and rule.itemID then AddItem(rule.itemID, rule.name) b:SetText("") b:ClearFocus()
            else f.status.Show_("Item not known: use an item link or its ID.", true) end
        end)
        UI.AcceptItemLinks(box, function(link, b)
            local id = tonumber(link:match("item:(%d+)"))
            if id then AddItem(id, link:match("%[(.-)%]")) b:SetText("") end
        end)
        C:Add(box, UI.ROW + 8)

        -- the table
        local head = CreateFrame("Frame", nil, f)
        head:SetSize(W, 18)
        C:Add(head, 20)
        local function Head(text, x, w)
            local h = UI.Label(head, text, "GameFontNormalSmall")
            h:SetPoint("LEFT", x, 0)
            if w then h:SetWidth(w) h:SetJustifyH("CENTER") end
            h:SetTextColor(0.7, 0.7, 0.7)
            return h
        end
        f.headItem = Head("Excluded Item", 6)
        f.heads = { trade = Head("in Trade", COL_TRADE, 60), mail = Head("in Mail", COL_MAIL, 60), loot = Head("in Loot", COL_LOOT, 60) }
        local list = CreateFrame("Frame", nil, f)
        list:SetSize(W, ROWS * ROW_H)
        C:Add(list, ROWS * ROW_H + 4)
        f.empty = UI.Label(list, "No items yet: drop one on the button above.", "GameFontDisableSmall")
        f.empty:SetPoint("TOPLEFT", 6, -4)
        f.rows = {}
        local TIPS = {
            trade = { "in Trade", "Ticked: MMT never puts this item into a trade (role rules and sharing)." },
            mail = { "in Mail", "Ticked: \"Mail to team\" never mails this item." },
            loot = { "in Loot", "Ticked: the team never loots this item. As master looter, Loot Distribution leaves it on the corpse instead of handing it out." },
        }
        local function Box(row, x, what)
            local cb = CreateFrame("Button", nil, row)
            cb:SetSize(16, 16)
            cb:SetPoint("LEFT", x + 22, 0)
            UI.Fill(cb, 0.12, 0.12, 0.12, 1)
            UI.Border(cb, 0.35, 0.35, 0.35, 1)
            cb.mark = cb:CreateTexture(nil, "ARTWORK")
            cb.mark:SetPoint("TOPLEFT", 3, -3) cb.mark:SetPoint("BOTTOMRIGHT", -3, 3)
            cb.mark:SetColorTexture(A[1], A[2], A[3], 1)
            cb:SetScript("OnClick", function()
                local e = row.entry
                if e then e[what] = not e[what] or nil cb.mark:SetShown(e[what] == true) ns.Refresh() end
            end)
            UI.Tooltip(cb, TIPS[what][1], TIPS[what][2])
            return cb
        end
        for i = 1, ROWS do
            local row = CreateFrame("Frame", nil, list)
            row:SetSize(W, ROW_H)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            if i % 2 == 0 then UI.Fill(row, 1, 1, 1, 0.03) end
            row:EnableMouse(true)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16) row.icon:SetPoint("LEFT", 6, 0)
            row.name = UI.Label(row, "", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", 28, 0)
            row.name:SetJustifyH("LEFT") row.name:SetWordWrap(false)
            row.boxes = { trade = Box(row, COL_TRADE, "trade"), mail = Box(row, COL_MAIL, "mail"), loot = Box(row, COL_LOOT, "loot") }
            row.Remove = function()
                local e = row.entry
                if not e then return end
                if AllColumns() then
                    e.trade, e.mail, e.loot = nil, nil, nil
                else
                    for k in pairs(Mine()) do e[k] = nil end
                end
                if not (e.trade or e.mail or e.loot) then
                    local l = List()
                    for j, x in ipairs(l) do if x == e then table.remove(l, j) break end end
                end
                f.Layout() ns.Refresh()
            end
            row.del = UI.TextButton(row, "x", row.Remove, 18)
            row.del:SetPoint("RIGHT", -2, 0)
            row:SetScript("OnEnter", function(self)
                if not self.entry then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, self.entry.itemID)
                else GameTooltip:SetText(self.entry.name or "") end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            f.rows[i] = row
        end
        list:EnableMouseWheel(true)
        list:SetScript("OnMouseWheel", function(_, d)
            f.offset = math.max(0, math.min(#Shown() - ROWS, (f.offset or 0) - d))
            f.Layout()
        end)
        f.more = UI.Label(f, "", "GameFontDisableSmall")
        f.more:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", -4, -2)
        f.allCheck = UI.Check(f, 220, "Show Trade / Mail too", function() return ns.db.exclusionAllColumns end,
            function(v) ns.db.exclusionAllColumns = v or nil f.offset = 0 f.Layout() end,
            "Lists every item of the Exclusion List here, with its \"in Trade\" and \"in Mail\" ticks next to \"in Loot\" (the same list as on the Trade / Mail / Vendor page). Off: only the items the team never loots.")
        C:Add(f.allCheck, UI.ROW)
        -- bulk: every listed item gets all three ticks / the list emptied (this view's part of it)
        f.tickAll = UI.Button(f, 110, "Tick all", function()
            for _, e in ipairs(Shown()) do e.trade, e.mail, e.loot = true, true, true end
            f.status.Show_("Every item: never traded, mailed or looted.")
            f.Layout() ns.Refresh()
        end)
        UI.Tooltip(f.tickAll, "Tick all", "Ticks \"in Trade\", \"in Mail\" and \"in Loot\" on every item of the list.")
        C:Add(f.tickAll, 0)
        f.clear = ConfirmButton(f, 110, "Clear list", function()
            local l = List()
            if AllColumns() then
                wipe(l)
            else
                for i = #l, 1, -1 do
                    local e = l[i]
                    e.loot = nil
                    if not (e.trade or e.mail) then table.remove(l, i) end
                end
            end
            f.offset = 0
            f.status.Show_("List cleared.")
            f.Layout() ns.Refresh()
        end)
        f.clear:SetPoint("LEFT", f.tickAll, "RIGHT", 6, 0)
        C:Space(UI.ROW + 4)
        C:Add(f.status, UI.ROW)
        f:SetSize(W + 32, -C.y + 10)

        f.Layout = function()
            local loot, all = LootView(), AllColumns()
            f.title:SetText(loot and "Never Loot List" or "Exclusion List")
            f.intro:SetText(loot and "Items on this list are never looted by the team: as master looter, Loot Distribution leaves them on the corpse."
                or "Here you can add items and set them to be never traded or mailed, regardless if they are included in a role.")
            f.headItem:SetText(loot and not all and "Never Looted Item" or "Excluded Item")
            local cols = { trade = not loot or all, mail = not loot or all, loot = all }
            for k, h in pairs(f.heads) do h:SetShown(cols[k]) end
            local left = cols.trade and COL_TRADE or (W - 24)
            f.allCheck:SetShown(loot)
            f.allCheck.Refresh()
            f.tickAll:SetShown(all)
            f.clear:SetShown(loot)
            f.clear:ClearAllPoints()
            if all then f.clear:SetPoint("LEFT", f.tickAll, "RIGHT", 6, 0) else f.clear:SetPoint("TOPLEFT", f.tickAll, "TOPLEFT") end
            UI.Tooltip(f.clear, "Clear list", (all and "Takes every item off the Exclusion List: trade, mail and loot."
                or "Takes every item off the Never Loot List (items that are also never traded or mailed stay for that).")
                .. " Click twice.")
            local l = Shown()
            f.offset = math.max(0, math.min(f.offset or 0, #l - ROWS))
            for i, row in ipairs(f.rows) do
                local e = l[(f.offset or 0) + i]
                row.entry = e
                if e then
                    local name, _, q, _, _, _, _, _, _, tex = ns.ItemInfo(e.itemID)
                    e.name = name or e.name
                    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
                    row.name:SetWidth(left - 34)
                    row.name:SetText((c and c.hex or "|cffffffff") .. (e.name or ("item " .. e.itemID)) .. "|r")
                    row.icon:SetTexture(tex or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.itemID)) or 134400)
                    for k, bx in pairs(row.boxes) do
                        bx:SetShown(cols[k])
                        bx.mark:SetShown(e[k] == true)
                    end
                    UI.Tooltip(row.del, "Remove", all and "Takes the item off the Exclusion List (trade, mail and loot)."
                        or loot and "The team loots this item again." or "Takes the item off the Exclusion List.")
                    row:Show()
                else
                    row:Hide()
                end
            end
            f.empty:SetShown(#l == 0)
            f.more:SetText(#l > ROWS and ("%d-%d of %d (mouse wheel)"):format((f.offset or 0) + 1, math.min(#l, (f.offset or 0) + ROWS), #l) or "")
        end
        UI.CloseOnEscape(f)
        exclusionWin = f
    end
    if f.view ~= view then f.offset = 0 end
    f.view = view
    f.status.Show_("")
    f.Layout()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", window, "TOPRIGHT", 6, 0)
    f:Show()
    return f
end

ns.RegisterPage("trade", "Trade / Mail / Vendor", function(page)
    local TOP = Intro(page, "I hate clicking all the stuff... make it staahp!")
    local X2 = TILE_W + TILE_GAP

    -- Vendor: Buy & Sell (left, full height) ----------------------------------------------
    local vt, V = Tile(page, 0, TOP, TILE_W, 564 + TOP, "Vendor: Buy & Sell", "Interface\\Icons\\INV_Misc_Coin_01")
    V:Header("Vendor")
    V:Check("Sell grey items", Opt("merchant", "sellGrey"))
    V:Check("Repair automatically", Opt("merchant", "repair"))
    local gg, sg = Opt("merchant", "guildRepair")
    V:Check("Use guild funds if allowed", gg, sg, "Falls back to your own gold.")
    V:Check("Print results to chat", Opt("merchant", "report"))
    local gml, sml = Opt("merchant", "tellLeader")
    V:Check("Tell the leader", gml, sml, "Items sold and repairs of the other characters are posted in the leader's chat (the FTL leader; without one online, the group leader if in the team, else the first online team member).")
    local gm, sm = Opt("merchant", "moneyFormat")
    V:Cycle("Money format", {
        { value = "text",  text = "1 gold 2 silver" },
        { value = "short", text = "1g 2s 3c" },
        { value = "coins", text = "Coin icons" },
    }, gm, sm)

    V:Header("Buy List")
    local gby, sby = Opt("merchant", "buy")
    V:Check("Buy up to the count at vendors", gby, sby,
        "At a vendor that sells them, the items below are bought until the character carries the quantity (gold only). Each item is bought by the characters chosen for it.")
    local function BuyList() ns.db.merchant.buyList = ns.db.merchant.buyList or {} return ns.db.merchant.buyList end
    local buySel   -- selected row (index)
    local COL_QTY, COL_CHARS = TILE_IN - 170, TILE_IN - 120   -- column starts: Quantity, Characters
    local head = CreateFrame("Frame", nil, vt)
    head:SetSize(TILE_IN, 16)
    for _, c in ipairs({ { "Item", 6 }, { "Quantity", COL_QTY }, { "Characters", COL_CHARS } }) do
        local l = UI.Label(head, c[1], "GameFontNormalSmall")
        l:SetPoint("LEFT", c[2], 0)
        l:SetTextColor(0.6, 0.6, 0.6)
    end
    V:Add(head, 16)
    local list = List(vt, TILE_IN, 4, 20, function(parent, i)
        local row = CreateFrame("Button", nil, parent)
        RowBackground(row, i)
        row.sel = UI.Fill(row, A[1], A[2], A[3], 0.18, "BORDER")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
        row.name = UI.Label(row, "")
        row.name:SetPoint("LEFT", 6, 0)
        row.name:SetWidth(COL_QTY - 12)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.count = UI.Label(row, "")
        row.count:SetPoint("LEFT", COL_QTY, 0)
        row.chars = UI.Label(row, "")
        row.chars:SetPoint("LEFT", COL_CHARS, 0)
        row.chars:SetPoint("RIGHT", -4, 0)
        row.chars:SetJustifyH("LEFT")
        row.chars:SetWordWrap(false)
        row:SetScript("OnClick", function() buySel = row.index; page.OnRefresh() end)
        row:SetScript("OnDoubleClick", function() buySel = row.index; ns.OpenBuyEditor(page:GetParent(), row.index, page.OnRefresh) end)
        row:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(e.name or ("item " .. tostring(e.itemID)))
            GameTooltip:AddLine(("Buy up to %d"):format(e.count or 0), 1, 1, 1)
            local chars = ns.BuyEntryChars(e)
            if not chars then
                GameTooltip:AddLine("On every character", 0.7, 0.7, 0.7)
            else
                for _, k in ipairs(chars) do GameTooltip:AddLine(ns.ShownName(k), 0.7, 0.7, 0.7) end
            end
            GameTooltip:AddLine("Click to select, double-click to edit.", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, entry, index)
        row.index, row.entry = index, entry
        row.sel:SetShown(index == buySel)
        row.name:SetText(entry.name or ("item " .. tostring(entry.itemID)))
        row.count:SetText(tostring(entry.count or 0))
        local chars = ns.BuyEntryChars(entry)
        row.chars:SetText(not chars and "|cff999999all characters|r"
            or (#chars == 1 and ns.ShownName(chars[1]))
            or ("on " .. #chars .. " characters"))
    end)
    V:Add(list, 4 * 20 + 4)
    local noBuy = UI.Label(vt, "Nothing on the buy list yet.")
    noBuy:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -4)
    noBuy:SetTextColor(0.5, 0.5, 0.5)
    local third = math.floor((TILE_IN - 12) / 3)
    local addItem = UI.Button(vt, third, "Add Item", function() ns.OpenBuyEditor(page:GetParent(), nil, function(i) buySel = i; page.OnRefresh() end) end)
    V:Add(addItem, 0)
    local editItem = UI.Button(vt, third, "Edit", function()
        if buySel and BuyList()[buySel] then ns.OpenBuyEditor(page:GetParent(), buySel, page.OnRefresh) end
    end)
    editItem:SetPoint("LEFT", addItem, "RIGHT", 6, 0)
    local delItem = ConfirmButton(vt, third, "Delete", function()
        if buySel and BuyList()[buySel] then
            table.remove(BuyList(), buySel)
            buySel = nil
            page.OnRefresh()
        end
    end)
    delItem:SetPoint("LEFT", editItem, "RIGHT", 6, 0)
    V:Space(UI.ROW + 6)

    V:Header("Sell List")
    local gsr, ssr = Opt("merchant", "sellRole")
    V:Cycle("Also sell items of role", RoleChoices, gsr, ssr)
    local gnr, snr = Opt("merchant", "neverRole")
    V:Cycle("Never sell items of role", RoleChoices, gnr, snr)
    V:Note("Lists are roles from the Roles page: create e.g. \"Sell\" and \"Keep\" with their items and rules (item, quality, Bind on Equip, item group). The never-sell list wins, greys included.")

    -- Trading (top right) ----------------------------------------------------------------
    local TRADE_H = 42 + UI.ROW + (UI.ROW + 2) + 58 + 64 + 8
    local tt, T = Tile(page, X2, TOP, TILE_W, TRADE_H, "Trading", "Interface\\Icons\\INV_Misc_Bag_07")
    local exclBtn = UI.Button(tt, 110, "Exclusion List", function() ns.OpenExclusionList(page:GetParent()) end)
    exclBtn:SetHeight(20)
    exclBtn:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -8, -8)
    UI.Tooltip(exclBtn, "Exclusion List", "Items MMT never trades or mails, even when a role includes them.")
    local gtr, str = Opt("trade", "enabled")
    T:Check("Fill trades from role rules", gtr, str,
        "When you open a trade with a team member, the items their roles ask for go into the trade window. You still accept the trade yourself. /mmt trade fills it again.")
    local function ShareChoices()
        local l = {}
        for _, c in ipairs(RoleChoices()) do if c.value ~= "" then l[#l + 1] = c end end
        return l
    end
    T:Add(UI.MultiDropdown(tt, TILE_IN, "Share among team", ShareChoices,
        function(role) ns.ShareRoles() return ns.db.trade.shareRoles[role] and true or false end,
        function(role)
            ns.ShareRoles()
            ns.db.trade.shareRoles[role] = not ns.db.trade.shareRoles[role] or nil
        end), UI.ROW + 2)
    T:Note("Pick any number of roles. The items of each are split evenly among the members that have that role. In a trade between two of them, the one above the even share gives what the other is missing.")
    local shareInfo = UI.Label(tt, "")
    shareInfo:SetWidth(TILE_IN)
    shareInfo:SetJustifyH("LEFT")
    shareInfo:SetJustifyV("TOP")
    shareInfo:SetTextColor(0.75, 0.75, 0.75)
    T:Add(shareInfo, 64)

    -- Bank & Mailing (bottom right) ---------------------------------------------------------
    local BY = TOP - TRADE_H - 8
    local _, B = Tile(page, X2, BY, TILE_W, 564 + BY, "Bank & Mailing", "Interface\\Icons\\INV_Letter_15")
    B:Header("Mail")
    local gme, sme = Opt("mail", "enabled")
    B:Check("\"Mail to team\" at the mailbox", gme, sme,
        "Shows the \"MMT Auto-Mailing\" window next to the mailbox: its \"Mail to team\" button sends every item in your bags that another team member's role wants to that member (team order; items your own role wants stay), 12 items per mail. The window lists each mail (to whom, for which role, how many items; a stack counts as one), each can be ticked off, and shows the postage.")
    local ggt, sgt = Opt("mail", "goldTo")
    B:Cycle("Also mail gold to", MemberChoices, ggt, sgt)
    local gkg, skg = Opt("mail", "keepGold")
    B:Slider("Keep gold", 0, 1000, 10, gkg, skg)

    B:Header("Guild bank")
    local gge, sge = Opt("gbank", "enabled")
    B:Check("\"Deposit\" button at the guild bank", gge, sge,
        "Puts the items of the role below into the chosen tab, and optionally the gold above the amount to keep.")
    local ggr, sgr = Opt("gbank", "role")
    B:Cycle("Deposit items of role", RoleChoices, ggr, sgr)
    local gtb, stb = Opt("gbank", "tab")
    B:Slider("Tab", 1, 8, 1, gtb, stb)
    local ggg, sgg = Opt("gbank", "gold")
    B:Check("Also deposit gold above \"Keep gold\"", ggg, sgg)
    local gbk, sbk = Opt("gbank", "keepGold")
    B:Slider("Keep gold (guild bank)", 0, 1000, 10, gbk, sbk)

    page.OnRefresh = function()
        local entries = BuyList()
        if buySel and not entries[buySel] then buySel = nil end
        list:Render(entries)
        noBuy:SetShown(#entries == 0)
        editItem:SetAlpha(buySel and 1 or 0.4)
        delItem:SetAlpha(buySel and 1 or 0.4)
        shareInfo:SetText(ns.ShareSummary and ns.ShareSummary() or "")
    end
end)

ns.RegisterPage("profiles", "Profiles", function(page)
    local TOP = Intro(page, "A profile holds all core settings: team, roles, Info window, automations and more. Profiles are shared by all characters on this account; each character uses one, new characters start with \"Default\".")
    -- account-wide, not part of a profile
    local mm = UI.Check(page, 300, "Show Minimap button",
        function() return ns.MinimapButtonShown and ns.MinimapButtonShown() end,
        function(v) if ns.SetMinimapButton then ns.SetMinimapButton(v) end end,
        "A button on the minimap: left-click opens these settings (like /mmt), right-click shows or hides the Info window, drag it to move it. This choice belongs to this account (all its characters and profiles).")
    mm:SetPoint("TOPLEFT", page, "TOPLEFT", 0, TOP + 2)
    TOP = TOP - UI.ROW - 4
    local X2 = TILE_W + TILE_GAP
    local TOP_H = 42 + 4 * (UI.ROW + 6) + 8
    local Y2 = TOP - TOP_H - 8
    local BOTTOM_H = 564 + Y2 - (UI.ROW + 4)   -- the status line goes below the tiles
    local half = math.floor((TILE_IN - 8) / 2)
    local copySource
    local status
    local function AskModules(done) ns.AskResetModules(done, function(msg) status.Show_(msg) end) end

    -- Active Profile (top left) ---------------------------------------------------------------
    local at, P = Tile(page, 0, TOP, TILE_W, TOP_H, "Active Profile", "Interface\\Icons\\INV_Misc_Book_11")
    local function ProfileChoices()
        local l = {}
        for _, name in ipairs(ns.ProfileNames()) do l[#l + 1] = { value = name, text = name } end
        return l
    end
    local active = UI.Cycle(at, TILE_IN, "Profile", ProfileChoices,
        function() return ns.CurrentProfileName() end,
        function(v) ns.SetProfile(v) end)
    P:Add(active, UI.ROW + 6)
    local usedBy = UI.Label(at, "")
    usedBy:SetTextColor(0.6, 0.6, 0.6)
    P:Add(usedBy, UI.ROW + 6)
    P:Space(UI.ROW + 6)
    local reset = ConfirmButton(at, half, "Reset profile", function()
        ns.ResetProfile()
        status.Show_("Profile reset to defaults.")
        AskModules("Profile reset to defaults.")
    end)
    P:Add(reset, 0)
    UI.Tooltip(reset, "Reset profile", "Puts every core setting of the active profile back to its default. Click twice to confirm.")
    local delete = ConfirmButton(at, half, "Delete profile", function()
        local name = ns.CurrentProfileName()
        if ns.DeleteProfile(name) then status.Show_(("Deleted \"%s\"."):format(name)) ns.Refresh() end
    end)
    delete:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    UI.Tooltip(delete, "Delete profile", "Deletes the active profile. Default can't be deleted. Characters using it go back to Default.")

    -- New & Copy (top right) ----------------------------------------------------------------------
    local nt, N = Tile(page, X2, TOP, TILE_W, TOP_H, "New & Copy", "Interface\\Icons\\INV_Misc_Note_02")
    local newName = UI.EditBox(nt, TILE_IN, "New profile name", nil)
    N:Add(newName, UI.ROW + 6)
    local function Create(copy)
        local name = ns.Trim(newName:GetText())
        if ns.CreateProfile(name, copy and ns.db or nil) then
            ns.SetProfile(name)
            newName:SetText(""); newName:ClearFocus()
            status.Show_(("Created \"%s\"%s."):format(name, copy and " as a copy of the current settings" or ""))
            if not copy then AskModules(("Created \"%s\"."):format(name)) end
        else
            status.Show_("Enter a name that isn't used yet.", true)
        end
        ns.Refresh()
    end
    newName:SetScript("OnEnterPressed", function() Create(true) end)
    local copyCurrent = UI.Button(nt, half, "Copy current", function() Create(true) end)
    N:Add(copyCurrent, 0)
    UI.Tooltip(copyCurrent, "Copy current", "Creates the profile with the name above as a copy of the active one and switches to it.")
    local empty = UI.Button(nt, half, "New (empty)", function() Create(false) end)
    empty:SetPoint("LEFT", copyCurrent, "RIGHT", 8, 0)
    UI.Tooltip(empty, "New (empty)", "Creates the profile with the name above with default settings and switches to it.")
    N:Space(UI.ROW + 6)
    local source = UI.Cycle(nt, TILE_IN, "Copy from", function()
        local l = {}
        for _, name in ipairs(ns.ProfileNames()) do
            if name ~= ns.CurrentProfileName() then l[#l + 1] = { value = name, text = name } end
        end
        if #l == 0 then l[1] = { value = nil, text = "-" } end
        return l
    end, function() return copySource end, function(v) copySource = v end)
    N:Add(source, UI.ROW + 6)
    local copy = ConfirmButton(nt, TILE_IN, "Copy into active profile", function()
        if copySource and ns.CopyProfileInto(copySource) then
            status.Show_(("Copied \"%s\" into \"%s\"."):format(copySource, ns.CurrentProfileName()))
        end
    end)
    N:Add(copy, UI.ROW + 6)
    UI.Tooltip(copy, "Copy into active profile", "Overwrites the active profile with the settings of the profile chosen above. Click twice to confirm.")

    -- Share with the Team (bottom left) ---------------------------------------------------------
    local stile, S = Tile(page, 0, Y2, TILE_W, BOTTOM_H, "Share with the Team", "Interface\\Icons\\Spell_Arcane_Blink")
    S:Note("Sends the active profile to your group and online team members (same as /mmt sync): team, roles, Info window incl. its position, automations, which modules are on or off, and the look and size of the settings window.")
    S:Note("With \"Use guild channel\" (Team page) and every recipient in your guild, the settings of the modules go along too; otherwise every module page has its own Sync button.")
    S:Space(4)
    local syncButton = UI.SyncButton(page, "Sync to team", function() ns.SendProfileToTeam() end, "Sync core settings",
        "Same as /mmt sync: sends the core settings of the active profile (team, roles, Info window incl. its position, automations, distance window), which modules are on or off and the settings window's look and size (Help > Appearance) to your group and online team members. With \"Use guild channel\" and every recipient in your guild, the settings of the modules go along too; otherwise every module page has its own Sync button. Each recipient gets a dialog to accept them (or accepts on its own, see the option below the button).")
    syncButton:ClearAllPoints()
    syncButton:SetParent(stile)
    syncButton:SetWidth(TILE_IN)
    S:Add(syncButton, 32)
    local autoAccept = UI.Check(stile, TILE_IN, "Auto-accept synced settings",
        function() return MMTDB.autoAcceptSync and true or false end,
        function(v) MMTDB.autoAcceptSync = v or nil end,
        "Settings a team member syncs to this client (core settings and module settings) are applied without the dialog. Only team members can sync. This option belongs to this account (all its characters) and is never synced itself.")
    S:Add(autoAccept, UI.ROW)

    -- Export / Import (bottom right) ------------------------------------------------------------------
    local et, E = Tile(page, X2, Y2, TILE_W, BOTTOM_H, "Export / Import", "Interface\\Icons\\INV_Scroll_04")
    E:Note("For another account or a backup: Export, copy the text (Ctrl+A, Ctrl+C) and paste it there, then Import. Import uses the name in New & Copy if filled, overwrites a profile of that name and activates it.")
    local anonymous = false
    local anon = UI.Check(et, TILE_IN, "Export without names (Paladin1, Mage1, ...)",
        function() return anonymous end, function(v) anonymous = v and true or false end,
        "Every team member becomes their class and a number (in team order) everywhere in the export: the team list, the roles and the settings of the modules kept per character. To share your setup without your characters' names. Your own profile isn't changed.")
    E:Add(anon, UI.ROW)
    local areaH = BOTTOM_H + E.y - (UI.ROW + 6) - 10
    local area = UI.TextArea(et, TILE_IN, areaH)
    E:Add(area, areaH + 6)
    local export = UI.Button(et, half, "Export", function()
        area.edit:SetText(ns.ExportProfile(anonymous))
        area.edit:SetFocus()
        area.edit:HighlightText()
        status.Show_(("Exported \"%s\"%s."):format(ns.CurrentProfileName(), anonymous and " without names" or ""))
    end)
    E:Add(export, 0)
    local import = UI.Button(et, half, "Import", function()
        local name, data = ns.ParseExport(area.edit:GetText())
        if not name then
            status.Show_("That text is not a valid MMT profile export.", true)
            return
        end
        local custom = ns.Trim(newName:GetText())
        if custom ~= "" then name = custom end
        ns.ImportProfile(name, data, true)
        area.edit:SetText("")
        newName:SetText("")
        status.Show_(("Profile \"%s\" imported and activated."):format(name))
        ns.Refresh()
    end)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)

    -- one status line for the whole page, below the tiles
    status = StatusLine(page)
    status:SetWidth(PAGE_W)
    status:SetPoint("TOPLEFT", page, "TOPLEFT", 4, Y2 - BOTTOM_H - 6)

    page.OnRefresh = function()
        if not copySource or copySource == ns.CurrentProfileName() or not MMTDB.profiles[copySource] then
            copySource = nil
            for _, name in ipairs(ns.ProfileNames()) do
                if name ~= ns.CurrentProfileName() then copySource = name break end
            end
        end
        source.Refresh()
        local canDelete = ns.CurrentProfileName() ~= "Default"
        delete:SetEnabled(canDelete)
        delete:SetAlpha(canDelete and 1 or 0.4)
        local n = 0
        for _, prof in pairs(MMTDB.profileKeys or {}) do if prof == ns.CurrentProfileName() then n = n + 1 end end
        usedBy:SetText(("Used by %d character%s on this account."):format(n, n == 1 and "" or "s"))
        copy:SetAlpha(copySource and 1 or 0.4)
    end
end)

---------------------------------------------------------------------------
-- Manage modules
---------------------------------------------------------------------------
ns.RegisterPage("modules", "Modules", function(page)
    local col = UI.Column(page, 0, 0, PAGE_W)
    local header = col:Header("Installed modules")
    col:Note("Modules add features on top of the core. Each one is its own addon (folder MMT_<Name>), so it can also be switched on and off in the game's AddOns list.")

    local status

    -- "github.com/..." link: click shows it ready to copy (the game can't open links)
    local function LinkButton(parent)
        local b = CreateFrame("Button", nil, parent)
        b:SetHeight(14)
        b.text = UI.Label(b, "")
        b.text:SetPoint("LEFT")
        b.text:SetTextColor(A[1], A[2], A[3])
        b:SetScript("OnClick", function(self) if self.url then UI.CopyText(self.label or "Repository", self.url) end end)
        b:SetScript("OnEnter", function(self)
            self.text:SetTextColor(1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.url or "")
            GameTooltip:AddLine("Click to copy the link.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self) self.text:SetTextColor(A[1], A[2], A[3]); GameTooltip:Hide() end)
        b.Set = function(self, url, label)
            self.url, self.label = url, label
            self.text:SetText(url and url:gsub("^https?://", ""):gsub("/$", "") or "")
            self:SetWidth(self.text:GetStringWidth() + 2)
            self:SetShown(url ~= nil)
        end
        return b
    end

    -- core line
    local core = CreateFrame("Frame", nil, page)
    core:SetSize(PAGE_W, 18)
    core.text = UI.Label(core, "")
    core.text:SetPoint("LEFT", 8, 0)
    core.text:SetTextColor(0.7, 0.7, 0.7)
    core.link = LinkButton(core)
    core.link:SetPoint("LEFT", core.text, "RIGHT", 6, 0)
    col:Add(core, 24)

    -- module rows (scroll with the mouse wheel when there are more)
    local ROWS, ROW_H = 7, 58
    local function MakeRow(list, i)
        local row = CreateFrame("Frame", nil, list)
        RowBackground(row, i)
        row.check = UI.Check(row, 24, "", function() return row.entry and row.on end, function(v)
            if not row.entry then return end
            local result = ns.SetModuleEnabled(row.entry, v)
            if result == "reload" then
                status.Show_(row.entry.title .. " is enabled and loads after a UI reload.")
            elseif result == "active" then
                status.Show_(row.entry.title .. " is on.")
            else
                status.Show_(row.entry.title .. " is off and won't load at the next login.")
            end
            ns.RefreshConfig()
        end)
        row.check:SetPoint("TOPLEFT", 8, -6)
        row.title = UI.Label(row, "", "GameFontNormal")
        row.title:SetPoint("TOPLEFT", 34, -8)
        row.version = UI.Label(row, "")
        row.version:SetPoint("LEFT", row.title, "RIGHT", 6, 0)
        row.version:SetTextColor(0.5, 0.5, 0.5)
        row.state = UI.Label(row, "")
        row.state:SetPoint("TOPRIGHT", -8, -8)
        row.notes = UI.Label(row, "")
        row.notes:SetPoint("TOPLEFT", 34, -24)
        row.notes:SetPoint("RIGHT", -8, 0)
        row.notes:SetJustifyH("LEFT")
        row.notes:SetWordWrap(false)
        row.notes:SetTextColor(0.6, 0.6, 0.6)
        row.author = UI.Label(row, "")
        row.author:SetPoint("TOPLEFT", 34, -39)
        row.author:SetTextColor(0.5, 0.5, 0.5)
        row.link = LinkButton(row)
        row.link:SetPoint("LEFT", row.author, "RIGHT", 6, 0)
        -- notes are cut to one line: the full text in the tooltip
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(e.title .. (e.version and ("  v" .. e.version) or ""))
            if e.notes ~= "" then GameTooltip:AddLine(e.notes, 1, 1, 1, true) end
            GameTooltip:AddLine("Addon folder: " .. e.addon, 0.6, 0.6, 0.6)
            if e.author then GameTooltip:AddLine("Author: " .. e.author, 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end
    local function FillRow(row, e)
        row.entry = e
        local active = e.module and e.module.enabled
        row.on = active or (not e.loaded and e.enabled)
        row.title:SetText(e.title)
        row.version:SetText(e.version and ("v" .. e.version) or "")
        row.notes:SetText(e.notes)
        row.author:SetText(e.author and ("by " .. e.author) or "author unknown")
        row.link:Set(e.repo, e.title .. " repository")
        if active then
            row.state:SetText("on"); row.state:SetTextColor(0.4, 1, 0.4)
        elseif e.loaded then
            row.state:SetText("off"); row.state:SetTextColor(0.6, 0.6, 0.6)
        elseif e.enabled then
            row.state:SetText("loads after reload"); row.state:SetTextColor(1, 0.85, 0.2)
        else
            row.state:SetText("off (not loaded)"); row.state:SetTextColor(0.6, 0.6, 0.6)
        end
        row.check.Refresh()
    end
    local list = List(page, PAGE_W, ROWS, ROW_H, MakeRow, FillRow)
    col:Add(list, ROWS * ROW_H + 4)
    local more = UI.Label(page, "")
    more:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", -4, 0)
    more:SetTextColor(0.5, 0.5, 0.5)

    local none = UI.Label(page, "No modules installed. Put module folders (e.g. MMT_ItemCompare) next to the MMT folder in Interface/AddOns.")
    none:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -8)
    none:SetWidth(PAGE_W - 16)
    none:SetJustifyH("LEFT")
    none:SetTextColor(0.5, 0.5, 0.5)

    status = StatusLine(page)
    status:SetWidth(PAGE_W)
    col:Add(status, UI.ROW)

    -- reload notice at the bottom, only while a reload is needed
    local notice = CreateFrame("Frame", nil, page)
    notice:SetPoint("BOTTOMLEFT", 0, 0)
    notice:SetSize(PAGE_W - 190, 34)   -- the sync button sits to the right
    UI.Fill(notice, 1, 0.85, 0.2, 0.08)
    UI.Border(notice, 1, 0.85, 0.2, 0.35)
    local reload = UI.Button(notice, 120, "Reload UI", function()
        UI.AskReload("Reload the UI now, so the module changes take effect?")
    end)
    reload:SetPoint("RIGHT", -7, 0)
    reload.label:SetTextColor(1, 0.85, 0.2)
    notice.text = UI.Label(notice, "")
    notice.text:SetPoint("LEFT", 10, 0)
    notice.text:SetPoint("RIGHT", reload, "LEFT", -10, 0)
    notice.text:SetJustifyH("LEFT")
    notice.text:SetTextColor(1, 0.85, 0.2)
    notice:Hide()

    UI.SyncButton(page, "Sync to team", function() ns.SendModuleStates() end, "Sync module on/off",
        "Same as /mmt sync modules: sends which modules are on or off to your group and online team members; they switch theirs the same way (after a dialog, unless they accept syncs automatically). Modules switched on there may need a UI reload. Module settings are not included: every module page has its own Sync button. /mmt sync sends this too, with the core settings.")

    page.OnRefresh = function()
        local v, author, repo = ns.AddOnInfo("MMT")
        core.text:SetText(("Core: MMT %s%s"):format(v or ns.version, author and ("  by " .. author) or ""))
        core.link:Set(repo, "MMT repository")

        -- switched-on modules first, then the others (each by name)
        local entries = ns.InstalledModules()
        local function On(e) return ((e.module and e.module.enabled) or (not e.loaded and e.enabled)) and true or false end
        table.sort(entries, function(a, b)
            if On(a) ~= On(b) then return On(a) end
            return a.title < b.title
        end)
        local on = 0
        for _, e in ipairs(entries) do if On(e) then on = on + 1 end end
        if header and header.SetText then header:SetText(("Installed modules (%d of %d)"):format(on, #entries)) end
        list:Render(entries)
        more:SetText(#entries > ROWS and ("%d modules, scroll for more"):format(#entries) or "")
        none:SetShown(#entries == 0)

        local pending = ns.PendingReload()
        if #pending > 0 then
            notice.text:SetText("Reload needed: " .. table.concat(pending, ", ") .. (#pending == 1 and " loads" or " load")
                .. " after a UI reload.")
            notice:Show()
        elseif ns.reloadNeeded then
            notice.text:SetText("Reload the UI to finish the module changes.")
            notice:Show()
        else
            notice:Hide()
        end
    end
end)
