-- MMT: Quick Setup, a small window for new users. Shown once, at the first
-- login with an empty team (a team already set up, also by a sync, never sees
-- it). "/mmt setup" opens it again. Closing it marks it as seen
-- (MMTDB.quickSetupDone).

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT

local WIN_W = 440
local ROWS, ROW_H = 10, 18
local win

local function H() return ns.ConfigHelpers end

local function Done()
    MMTDB.quickSetupDone = true
    if win then win:Hide() end
end

-- the team list: dot (green = online with MMT, grey = offline), name in class colour
local function RefreshList()
    if not (win and win:IsShown()) then return end
    local keys = ns.SortedMembers()
    for i = 1, ROWS do
        local r = win.rows[i]
        local key = keys[i]
        if key then
            local m = ns.db.team[key]
            local c = m and m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
            r.name:SetText(ns.ShownName(key) .. (ns.IsSelf(key) and "  |cff808080(you)|r" or ""))
            r.name:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
            local on = ns.IsSelf(key) or (ns.IsOnline and ns.IsOnline(key))
            r.dot:SetColorTexture(on and 0.3 or 0.4, on and 0.9 or 0.4, on and 0.3 or 0.4, 1)
            r.key = key
            r:Show()
        else
            r.key = nil
            r:Hide()
        end
    end
    local more = #keys - ROWS
    win.more:SetText(more > 0 and ("... and " .. more .. " more") or "")
    win.empty:SetShown(#keys == 0)
end

local function Build()
    if win then return win end
    local Tile = H().Tile
    win = CreateFrame("Frame", "MMTQuickSetup", UIParent)
    win:SetFrameStrata("DIALOG")
    win:SetPoint("CENTER", 0, 60)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    UI.Fill(win, 0.05, 0.05, 0.06, 0.96)
    UI.Border(win, A[1], A[2], A[3], 0.45)
    if UI.CloseOnEscape then UI.CloseOnEscape(win) end
    win:SetScript("OnHide", function() MMTDB.quickSetupDone = true end)

    local title = UI.Label(win, "(MMT) Manage My Team - Quick Setup", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetTextColor(A[1], A[2], A[3])
    local x = UI.Button(win, 22, "x", Done)
    x:SetPoint("TOPRIGHT", -8, -7)
    local line = win:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(A[1], A[2], A[3], 0.35)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 8, -34) line:SetPoint("TOPRIGHT", -8, -34)

    local intro = UI.Label(win, "Welcome! Here are quick steps to get you going with MMT.")
    intro:SetPoint("TOPLEFT", 12, -44)
    intro:SetWidth(WIN_W - 24)
    intro:SetJustifyH("LEFT")
    intro:SetTextColor(0.85, 0.85, 0.85)

    local IN = WIN_W - 24
    local y = -66

    -- 1) invite
    local t1, c1 = Tile(win, 12, y, IN, 92, "1) Invite your characters into a group", "Interface\\Icons\\Spell_Holy_PrayerOfFortitude")
    c1:Note("Invite all characters of your team into one group.")
    c1:Note("If you are using ISBoxer, press the key combination: |cffffd100Shift + Alt + I|r")
    y = y - 92 - 8

    -- 2) add group + team list
    local LIST_H = 42 + (UI.ROW + 6) + 20 + ROWS * ROW_H + 18 + 8
    local t2, c2 = Tile(win, 12, y, IN, LIST_H, "2) Add your group to the team", "Interface\\Icons\\INV_Misc_GroupNeedMore")
    local status = UI.Label(t2, "", "GameFontNormalSmall")
    local add = UI.Button(t2, 120, "Add Group", function()
        local n = ns.AddGroupMembers()
        status:SetText(n > 0 and ("|cff66ff66Added " .. n .. " character(s) from your group.|r")
            or (IsInGroup() and "|cffffd100Nobody new in your group.|r" or "|cffff6666You aren't in a group yet (step 1).|r"))
        if ns.Refresh then ns.Refresh() end
        RefreshList()
    end)
    add:SetPoint("TOPLEFT", t2, "TOPLEFT", 8, c2.y)
    UI.Tooltip(add, "Add Group", "Adds you and everybody in your party or raid to the team (the same as Team > Add group in the settings).")
    status:SetPoint("LEFT", add, "RIGHT", 10, 0)
    status:SetPoint("RIGHT", t2, "RIGHT", -8, 0)
    status:SetJustifyH("LEFT")
    c2:Space(UI.ROW + 6)
    local head = UI.Label(t2, "Team Members:", "GameFontNormal")
    head:SetPoint("TOPLEFT", t2, "TOPLEFT", 8, c2.y)
    c2:Space(20)
    win.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, t2)
        r:SetSize(IN - 16, ROW_H)
        r:SetPoint("TOPLEFT", t2, "TOPLEFT", 8, c2.y - (i - 1) * ROW_H)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetSize(6, 6)
        r.dot:SetPoint("LEFT", 4, 0)
        r.name = UI.Label(r, "")
        r.name:SetPoint("LEFT", 16, 0)
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self) if self.key and ns.MemberTooltip then ns.MemberTooltip(self, self.key):Show() end end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        win.rows[i] = r
    end
    win.empty = UI.Label(t2, "No team members yet.", "GameFontNormalSmall")
    win.empty:SetPoint("TOPLEFT", t2, "TOPLEFT", 12, c2.y)
    win.empty:SetTextColor(0.5, 0.5, 0.5)
    win.more = UI.Label(t2, "", "GameFontNormalSmall")
    win.more:SetPoint("TOPLEFT", t2, "TOPLEFT", 12, c2.y - ROWS * ROW_H)
    win.more:SetTextColor(0.5, 0.5, 0.5)
    y = y - LIST_H - 8

    -- 3) done
    local t3, c3 = Tile(win, 12, y, IN, 110, "3) You're good to go", "Interface\\Icons\\Achievement_General")
    c3:Note("If the list populates after clicking Add Group, you're good to go and basics are now active, like loot distribution.")
    c3:Note("Customize your experience via |cffffd100/mmt|r or clicking the minimap button.")
    c3:Note("Enjoy!")
    y = y - 110 - 8

    local done = UI.Button(win, 120, "Done", Done)
    done:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, y)
    local open = UI.Button(win, 140, "Open settings", function() Done() ns.ToggleConfig("team") end)
    open:SetPoint("RIGHT", done, "LEFT", -8, 0)
    win:SetSize(WIN_W, -y + UI.ROW + 14)
    win:Hide()
    return win
end

function ns.ShowQuickSetup()
    Build()
    win:Show()
    RefreshList()
end

ns.Listen("TEAM_CHANGED", RefreshList)
ns.Listen("STATUS_CHANGED", RefreshList)

-- first login with an empty team: show it once
ns.OnLogin(function()
    C_Timer.After(2, function()
        if MMTDB.quickSetupDone then return end
        if ns.db and next(ns.db.team or {}) ~= nil then
            MMTDB.quickSetupDone = true   -- a team exists already: never needed
            return
        end
        ns.ShowQuickSetup()
    end)
end)
