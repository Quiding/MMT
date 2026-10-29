-- MMT Statistics: the module's page under MODULES, with the tabs Gold,
-- Kills and Settings.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local A = UI.ACCENT
local H = MMT.ConfigHelpers
local PAGE_W, COL_W, COL2_X = H.PAGE_W, H.COL_W, H.COL2_X

local ROWS, ROW_H = 6, 20
local COLS = { 0, 260, 420, 580 }   -- left edges: name | this character | other characters | combined
local COL_RIGHT = { nil, 400, 560, PAGE_W - 8 }

-- table: header + rows (name and three values), scrolls with the mouse wheel.
-- Row data: { name, v1, v2, v3, tip = function(tooltip) end, grey = bool }
local function Table(parent, headers)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(PAGE_W, ROW_H * (ROWS + 1) + 4)
    local head = {}
    for i, text in ipairs(headers) do
        local l = UI.Label(f, text, "GameFontNormal")
        if i == 1 then l:SetPoint("TOPLEFT", 8, -3)
        else l:SetPoint("TOPRIGHT", f, "TOPLEFT", COL_RIGHT[i], -3) end
        l:SetTextColor(A[1], A[2], A[3])
        head[i] = l
    end
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, -ROW_H)
    line:SetWidth(PAGE_W)
    f.list = H.List(f, PAGE_W, ROWS, ROW_H, function(list, i)
        local row = CreateFrame("Frame", nil, list)
        H.RowBackground(row, i)
        row.cells = {}
        for c = 1, 4 do
            local l = UI.Label(row, "")
            if c == 1 then
                l:SetPoint("LEFT", 8, 0)
                l:SetWidth(COLS[2] - 16)
                l:SetJustifyH("LEFT")
                l:SetWordWrap(false)
            else
                l:SetPoint("RIGHT", row, "LEFT", COL_RIGHT[c], 0)
                l:SetJustifyH("RIGHT")
            end
            row.cells[c] = l
        end
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not (self.data and self.data.tip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            self.data.tip(GameTooltip)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, d)
        row.data = d
        for c = 1, 4 do
            row.cells[c]:SetText(d[c] or "")
            if d.grey then row.cells[c]:SetTextColor(0.5, 0.5, 0.5)
            elseif c == 4 then row.cells[c]:SetTextColor(1, 1, 1)
            else row.cells[c]:SetTextColor(0.8, 0.8, 0.8) end
        end
    end)
    f.list:SetPoint("TOPLEFT", 0, -ROW_H - 2)
    f.empty = UI.Label(f, "")
    f.empty:SetPoint("TOPLEFT", 8, -ROW_H - 8)
    f.empty:SetTextColor(0.5, 0.5, 0.5)
    function f:Show_(rows, emptyText)
        self.list:Render(rows)
        self.empty:SetText(#rows == 0 and (emptyText or "") or "")
    end
    return f
end

-- simple ranked list: "1.  Name      12"
local function RankList(parent, width, n)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, n * 18)
    f.rows = {}
    for i = 1, n do
        local name = UI.Label(f, "")
        name:SetPoint("TOPLEFT", 8, -(i - 1) * 18)
        name:SetWidth(width - 70)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        local count = UI.Label(f, "")
        count:SetPoint("TOPRIGHT", -8, -(i - 1) * 18)
        count:SetJustifyH("RIGHT")
        f.rows[i] = { name, count }
    end
    function f:Show_(list, emptyText)
        for i, r in ipairs(self.rows) do
            local e = list[i]
            r[1]:SetText(e and ("%d.  %s"):format(i, e[1]) or (i == 1 and emptyText or ""))
            r[1]:SetTextColor(e and 0.85 or 0.5, e and 0.85 or 0.5, e and 0.85 or 0.5)
            r[2]:SetText(e and tostring(e[2]) or "")
        end
    end
    return f
end

---------------------------------------------------------------------------
-- Rows: you first, then the team; per member its account
---------------------------------------------------------------------------
local function Members()
    local me = MMT.PlayerFull()
    local list = { me }
    for _, key in ipairs(MMT.SortedMembers()) do
        if not MMT.IsSelf(key) then list[#list + 1] = key end
    end
    return list
end

-- field: "g" (gold) or "k" (kills); fmt formats a value
local function MemberRows(field, fmt, unit)
    local rows = {}
    for _, key in ipairs(Members()) do
        local acc = mod.AccountOf(key)
        local a = acc and mod.Account(acc)
        local own = a and a.chars[key]
        if not a or not own then
            rows[#rows + 1] = { MMT.ShownName(key), "no data", "", "", grey = true,
                tip = function(t)
                    t:SetText(MMT.ShownName(key))
                    t:AddLine("Nothing received yet: this character needs MMT with the Statistics module, and to have been online since.", 1, 1, 1, true)
                end }
        else
            local mine = own[field] or 0
            local others = 0
            for k, c in pairs(a.chars) do if k ~= key then others = others + (c[field] or 0) end end
            rows[#rows + 1] = { MMT.ShownName(key), fmt(mine), fmt(others), fmt(mine + others),
                tip = function(t)
                    t:SetText(mod.AccountLabel(acc))
                    local list = {}
                    for k, c in pairs(a.chars) do list[#list + 1] = { k, c } end
                    table.sort(list, function(x, y) return (x[2][field] or 0) > (y[2][field] or 0) end)
                    for _, e in ipairs(list) do
                        local c = e[2]
                        local age = c.s and ("  |cff888888" .. SecondsToTime(math.max(60, time() - c.s), true) .. " ago|r") or ""
                        t:AddDoubleLine(mod.CharName(e[1], c.c) .. age, fmt(c[field] or 0), 1, 1, 1, 1, 1, 1)
                    end
                    if not a.own and a.at then
                        t:AddLine(("Received %s ago."):format(SecondsToTime(math.max(60, time() - a.at), true)), 0.5, 0.5, 0.5)
                    end
                end }
        end
    end
    return rows
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
M.Page = function(_, page)
    local panels, buttons = {}, {}
    local current = "gold"
    local function Show(key)
        current = key
        for k, p in pairs(panels) do p:SetShown(k == key) end
        for k, b in pairs(buttons) do
            if k == key then b.label:SetTextColor(A[1], A[2], A[3]) else b.label:SetTextColor(0.7, 0.7, 0.7) end
        end
        if key ~= "settings" then mod.RequestIfOld() end
        if mod.Redraw then mod.Redraw() end
    end
    local tabs = { { "gold", "Gold" }, { "kills", "Kills" }, { "settings", "Settings" } }
    for i, t in ipairs(tabs) do
        local b = UI.Button(page, 120, t[2], function() Show(t[1]) end)
        b:SetPoint("TOPLEFT", (i - 1) * 130, 0)
        buttons[t[1]] = b
        local p = CreateFrame("Frame", nil, page)
        p:SetPoint("TOPLEFT", 0, -32)
        p:SetSize(PAGE_W, 520)
        panels[t[1]] = p
    end

    -- Gold ---------------------------------------------------------------------
    local g = panels.gold
    local gc = UI.Column(g, 0, 0, PAGE_W)
    gc:Header("Gold per account")
    local goldTable = Table(g, { "Account", "This Character", "Other Characters", "Combined" })
    gc:Add(goldTable, ROW_H * (ROWS + 1) + 14)
    gc:Header("Combined gold, last 60 days")
    local scope = UI.Dropdown(g, 300, "Show", mod.ScopeChoices,
        function() return M.db.chartScope end, function(v) M.db.chartScope = v; mod.Redraw() end)
    gc:Add(scope, UI.ROW + 6)
    local chart = mod.CreateChart(g, PAGE_W, 200)
    gc:Add(chart, 206)

    -- Kills --------------------------------------------------------------------
    local k = panels.kills
    local kc = UI.Column(k, 0, 0, PAGE_W)
    kc:Header("NPCs killed per account")
    local killTable = Table(k, { "Account", "This Character", "Other Characters", "Combined" })
    kc:Add(killTable, ROW_H * (ROWS + 1) + 14)
    local kscope = UI.Dropdown(k, 300, "Show", mod.ScopeChoices,
        function() return M.db.killScope end, function(v) M.db.killScope = v; mod.Redraw() end)
    kc:Add(kscope, UI.ROW + 10)
    local L = UI.Column(k, 0, kc.y, COL_W)
    L:Header("Top 10 NPCs killed")
    local top = RankList(k, COL_W, 10)
    L:Add(top, 10 * 18)
    local R = UI.Column(k, COL2_X, kc.y, COL_W)
    R:Header("Top 3 killed by NPC")
    local killers = RankList(k, COL_W, 3)
    R:Add(killers, 3 * 18 + 8)
    R:Note("Kills count where the game lets MMT see them: NPCs this character fought that died (targeted or with a nameplate) and the experience message. Deaths count the NPC that targeted you.")

    -- Settings -----------------------------------------------------------------
    local s = panels.settings
    local SL = UI.Column(s, 0, 0, COL_W)
    SL:Header("Tracking")
    SL:Check("Track gold", function() return M.db.trackGold end, function(v) M.db.trackGold = v; mod.RecordGold() end,
        "Records every character's gold at login, on every change and at logout: one record per day, kept for 60 days. Saved per account, not per profile.")
    SL:Check("Track kills and deaths", function() return M.db.trackKills end, function(v) M.db.trackKills = v end)
    SL:Check("Share with the team", function() return M.db.share end, function(v) M.db.share = v; if v then mod.SendSoon(1) end end,
        "Sends a summary of this account (characters with gold and kills, daily totals, top kills) to the team and keeps theirs. Needed for the other accounts in the tables and the chart.")
    SL:Header("Look")
    SL:Cycle("Money", {
        { value = "SHORT", text = "5g 32s 1c" },
        { value = "GOLD", text = "5g" },
        { value = "COINS", text = "Coin icons" },
    }, function() return M.db.money end, function(v) M.db.money = v; mod.Redraw() end)
    local SR = UI.Column(s, COL2_X, 0, COL_W)
    SR:Header("Data")
    SR:Note("Accounts: every WoW account keeps its own data. Other accounts are named after the team member that sent them (\"Account of Hunter 2\").")
    SR:Add(H.ConfirmButton(s, COL_W, "Clear this account's statistics", function()
        local st = mod.Store()
        wipe(st.chars)
        mod.RecordGold()
        mod.Redraw()
        MMT.Print("Statistics of this account cleared.")
    end), UI.ROW + 4)
    SR:Add(H.ConfirmButton(s, COL_W, "Forget other accounts", function()
        local st = mod.Store()
        wipe(st.accounts)
        wipe(st.memberAccount)
        mod.Redraw()
        MMT.Print("Statistics of other accounts forgotten. They come back when the team sends them again.")
    end), UI.ROW + 4)

    -- drawing --------------------------------------------------------------------
    function mod.Redraw()
        if not page:IsVisible() then return end
        if current == "gold" then
            goldTable:Show_(MemberRows("g", mod.Money))
            scope.Refresh()
            chart:SetData(mod.GoldSeries(M.db.chartScope), mod.Money)
        elseif current == "kills" then
            killTable:Show_(MemberRows("k", tostring))
            kscope.Refresh()
            top:Show_(mod.TopList(M.db.killScope, "kills", 10), "No kills recorded yet.")
            killers:Show_(mod.TopList(M.db.killScope, "deaths", 3), "Nobody killed you yet.")
        end
    end
    page:SetScript("OnShow", function() mod.Redraw() end)
    page.OnRefresh = function() mod.Redraw() end
    Show("gold")
end

-- /mmtstats and a key (key binding menu > MMT (Manage My Team) > Statistics) open the page
SLASH_MMTSTATS1 = "/mmtstats"
SlashCmdList.MMTSTATS = function() MMT.ToggleConfig("mod:Statistics") end
BINDING_HEADER_MMT_STATISTICS = "Statistics"
BINDING_NAME_MMT_STATISTICS = "Open / close Statistics"
function MMT_ToggleStatistics() if M.enabled then MMT.ToggleConfig("mod:Statistics") end end
