-- MMT Statistics: the module's page under MODULES, with the tabs Gold,
-- Kills, Quests and Settings.

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
            else   -- never wider than the column: a huge amount can't run into the next one
                l:SetPoint("RIGHT", row, "LEFT", COL_RIGHT[c], 0)
                l:SetWidth(COL_RIGHT[c] - (COL_RIGHT[c - 1] or COLS[2]) - 8)
                l:SetJustifyH("RIGHT")
                l:SetWordWrap(false)
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
    local tabs = { { "gold", "Gold" }, { "kills", "Kills" }, { "quests", "Quests" }, { "settings", "Settings" } }
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

    -- Quests -------------------------------------------------------------------
    local q = panels.quests
    local qc = UI.Column(q, 0, 0, PAGE_W)
    local qscope = UI.Dropdown(q, 300, "Show", {
        { value = "CHAR", text = "This character" },
        { value = "ACCOUNT", text = "This account" },
    }, function() return M.db.questScope end, function(v) M.db.questScope = v; mod.Redraw() end)
    qc:Add(qscope, UI.ROW + 8)
    -- three tiles: large number, small label below
    local TILE_GAP = 12
    local tileW = math.floor((PAGE_W - 4 * TILE_GAP) / 5)
    local tiles = {}
    for i, t in ipairs({ { "A", "accepted" }, { "C", "completed" }, { "X", "abandoned" },
                         { "S", "scanned quests" }, { "SC", "scanned completed" } }) do
        local tile = CreateFrame("Frame", nil, q)
        tile:SetSize(tileW, 84)
        tile:SetPoint("TOPLEFT", q, "TOPLEFT", (i - 1) * (tileW + TILE_GAP), qc.y)
        UI.Fill(tile, 1, 1, 1, 0.03)
        UI.Border(tile, 1, 1, 1, 0.08)
        tile.number = UI.Label(tile, "0", "GameFontHighlightHuge")
        pcall(tile.number.SetFont, tile.number, STANDARD_TEXT_FONT, 34, "")
        tile.number:SetPoint("TOP", 0, -12)
        tile.label = UI.Label(tile, t[2])
        tile.label:SetPoint("TOP", tile.number, "BOTTOM", 0, -4)
        tile.label:SetTextColor(0.6, 0.6, 0.6)
        tile:EnableMouse(true)
        tile:SetFrameLevel(q:GetFrameLevel() + 5)
        tile:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            -- (gsub returns two values: the count must not become SetText's colour)
            GameTooltip:SetText((t[2]:gsub("^%l", string.upper)), 1, 1, 1)
            GameTooltip:AddLine(self.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tiles[t[1]] = tile
    end
    tiles.A.number:SetTextColor(1, 0.82, 0)
    tiles.C.number:SetTextColor(0.4, 1, 0.4)
    tiles.X.number:SetTextColor(1, 0.4, 0.4)
    tiles.S.number:SetTextColor(0.6, 0.6, 0.6)
    tiles.SC.number:SetTextColor(0.6, 0.8, 0.6)
    qc:Space(84 + 16)
    qc:Header("Last 10 completed quests")
    -- small table: completed | character | quest | level | XP | money
    local QCOLS = {
        { x = 8, w = 110, head = "Completed" },
        { x = 124, w = 110, head = "Character" },
        { x = 240, w = 240, head = "Quest" },
        { right = 530, w = 44, head = "Level" },
        { right = 600, w = 64, head = "XP" },
        { right = PAGE_W - 8, w = 90, head = "Money" },
    }
    local recent = CreateFrame("Frame", nil, q)
    recent:SetSize(PAGE_W, ROW_H * 11 + 4)
    qc:Add(recent, ROW_H * 11 + 8)
    local function Cell(parent, col, y, template)
        local l = UI.Label(parent, "", template)
        if col.right then
            l:SetPoint("TOPRIGHT", parent, "TOPLEFT", col.right, y)
            l:SetJustifyH("RIGHT")
        else
            l:SetPoint("TOPLEFT", parent, "TOPLEFT", col.x, y)
            l:SetJustifyH("LEFT")
        end
        l:SetWidth(col.w)
        l:SetWordWrap(false)
        return l
    end
    for _, col in ipairs(QCOLS) do
        local l = Cell(recent, col, -3, "GameFontNormal")
        l:SetText(col.head)
        l:SetTextColor(A[1], A[2], A[3])
    end
    local qline = recent:CreateTexture(nil, "ARTWORK")
    qline:SetColorTexture(1, 1, 1, 0.08)
    qline:SetHeight(1)
    qline:SetPoint("TOPLEFT", 0, -ROW_H)
    qline:SetWidth(PAGE_W)
    local qrows = {}
    for i = 1, 10 do
        local row = CreateFrame("Frame", nil, recent)
        row:SetSize(PAGE_W, ROW_H)
        row:SetPoint("TOPLEFT", 0, -ROW_H - 2 - (i - 1) * ROW_H)
        H.RowBackground(row, i)
        row.cells = {}
        for c, col in ipairs(QCOLS) do row.cells[c] = Cell(row, col, -4) end
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.quest then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.quest.name)
            GameTooltip:AddLine(("Quest ID %d"):format(self.quest.id), 1, 1, 1)
            if self.quest.cl then GameTooltip:AddLine(("Completed at character level %d"):format(self.quest.cl), 1, 1, 1) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        qrows[i] = row
    end
    local qempty = UI.Label(recent, "No completed quests recorded yet.")
    qempty:SetPoint("TOPLEFT", 8, -ROW_H - 8)
    qempty:SetTextColor(0.5, 0.5, 0.5)
    qc:Note("Scanned quests (Settings tab) have no completion date, so they don't show here.")

    local function DrawQuests()
        qscope.Refresh()
        local s = mod.Store()
        local me = MMT.PlayerFull()
        -- accepted / completed / abandoned: tracked by MMT; scanned: found by the scan
        local n = { A = 0, C = 0, X = 0, S = 0, SC = 0 }
        local done = {}
        for key, c in pairs(s.chars) do
            if M.db.questScope ~= "CHAR" or key == me then
                for id, rec in pairs(c.quests or {}) do
                    if rec.scan then
                        n.S = n.S + 1
                        if rec.st == "C" then n.SC = n.SC + 1 end
                    elseif n[rec.st] then
                        n[rec.st] = n[rec.st] + 1
                    end
                    if rec.st == "C" and rec.tc then
                        done[#done + 1] = { id = id, rec = rec, key = key, class = c.class }
                    end
                end
            end
        end
        for k, tile in pairs(tiles) do tile.number:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(n[k]) or tostring(n[k])) end
        tiles.A.tip = "Quests MMT saw being accepted that are still open."
        tiles.C.tip = "Quests MMT saw being turned in (with date, experience and money)."
        tiles.X.tip = "Quests MMT saw being abandoned (and not accepted again since)."
        tiles.S.tip = "Quests found by \"Scan completed quests\" (Settings tab): the completed ones plus the quest log at the time of the scan. Not counted in the three tiles on the left."
        tiles.SC.tip = "Scanned quests the game reports as completed: no date, experience or money."
        table.sort(done, function(a, b) if a.rec.tc ~= b.rec.tc then return a.rec.tc > b.rec.tc end return a.id > b.id end)
        for i, row in ipairs(qrows) do
            local e = done[i]
            row:SetShown(e ~= nil)
            if e then
                local r = e.rec
                local name = r.n or ("Quest " .. e.id)
                row.quest = { id = e.id, name = name, cl = r.cl }
                row.cells[1]:SetText(date("%Y-%m-%d %H:%M", r.tc))
                row.cells[2]:SetText(mod.CharName(e.key, e.class))
                row.cells[3]:SetText(name)
                row.cells[4]:SetText(r.l and tostring(r.l) or "")
                row.cells[5]:SetText(r.xp and (BreakUpLargeNumbers and BreakUpLargeNumbers(r.xp) or tostring(r.xp)) or "")
                row.cells[6]:SetText(r.cp and mod.Money(r.cp) or "")
                for c = 1, 6 do row.cells[c]:SetTextColor(0.8, 0.8, 0.8) end
                row.cells[3]:SetTextColor(1, 1, 1)
            end
        end
        qempty:SetShown(#done == 0)
    end

    -- Settings -----------------------------------------------------------------
    local s = panels.settings
    local SL = UI.Column(s, 0, 0, COL_W)
    SL:Header("Tracking")
    SL:Check("Track gold", function() return M.db.trackGold end, function(v) M.db.trackGold = v; mod.RecordGold() end,
        "Records every character's gold after login and on every change: one record per day, kept for 60 days. Saved per account, not per profile.")
    SL:Check("Track kills and deaths", function() return M.db.trackKills end, function(v) M.db.trackKills = v end)
    SL:Check("Track quests", function() return M.db.trackQuests end, function(v) M.db.trackQuests = v end,
        "Records the quests each character accepts, completes (with its level, the experience and the money of the reward) and abandons. For the export (Quests). Not sent to the team.")
    SL:Check("Share with the team", function() return M.db.share end, function(v) M.db.share = v; if v then mod.SendNow() end end,
        "Sends a summary of this account (characters with gold and kills, daily totals, top kills) to the team and keeps theirs. Needed for the other accounts in the tables and the chart. Never in combat, at most as often as set below, and with the lowest priority.")
    SL:Slider("Send at most every (minutes)", 1, 30, 1, function() return M.db.sendEvery or 5 end,
        function(v) M.db.sendEvery = v end)
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
    local scanButton = UI.Button(s, COL_W, "Scan completed quests", function()
        local added, updated, inLog, unnamed = mod.ScanQuests()
        MMT.Print("Statistics: %d completed %s found that MMT didn't know yet%s%s.%s", added,
            added == 1 and "quest" or "quests",
            updated > 0 and (", %d marked as completed"):format(updated) or "",
            inLog > 0 and (", %d from the quest log added as accepted"):format(inLog) or "",
            unnamed > 0 and (" %d names are still loading from the game."):format(unnamed) or "")
    end)
    SR:Add(scanButton, UI.ROW + 4)
    UI.Tooltip(scanButton, "Scan completed quests", "Asks the game which quests this character has completed (like Questie does on its first login) and adds the ones MMT doesn't know yet, without date, experience and money. Quests MMT already tracked keep their details. Names and levels come from Questie's database when it is installed, else from the game.")
    SR:Add(H.ConfirmButton(s, COL_W, "Forget other accounts", function()
        local st = mod.Store()
        wipe(st.accounts)
        wipe(st.memberAccount)
        mod.Redraw()
        MMT.Print("Statistics of other accounts forgotten. They come back when the team sends them again.")
    end), UI.ROW + 4)

    -- Export (CSV) ---------------------------------------------------------------
    local EX = UI.Column(s, 0, math.min(SL.y, SR.y) - 4, PAGE_W)
    EX:Header("Export (CSV)")
    local ey = EX.y
    local EL = UI.Column(s, 0, ey, COL_W)
    EL:Cycle("Data", mod.EXPORT_KINDS, function() return M.db.exportKind end, function(v) M.db.exportKind = v end)
    local escope = UI.Dropdown(s, COL_W, "Accounts", mod.ScopeChoices,
        function() return M.db.exportScope end, function(v) M.db.exportScope = v end)
    EL:Add(escope, UI.ROW + 2)
    local ER = UI.Column(s, COL2_X, ey, COL_W)
    ER:Cycle("Separator", {
        { value = ",", text = "Comma (1234.56)" },
        { value = ";", text = "Semicolon (1234,56)" },
    }, function() return M.db.exportSep end, function(v) M.db.exportSep = v end)
    local area = UI.TextArea(s, PAGE_W, 120)
    local estatus = UI.Label(s, "")
    estatus:SetTextColor(0.6, 0.6, 0.6)
    local exportButton = UI.Button(s, COL_W, "Export", function()
        local text, rows = mod.ExportCSV(M.db.exportKind, M.db.exportScope, M.db.exportSep)
        area.edit:SetText(text)
        area.edit:SetFocus()
        area.edit:HighlightText()
        if rows == 0 then
            estatus:SetText(M.db.exportKind == "GOLD_CHAR"
                and "No rows: gold per character is only kept for this account (others send daily totals)."
                or "No rows: nothing recorded for these accounts yet.")
        else
            estatus:SetText(("%d %s. Copy with Ctrl+A, Ctrl+C and paste into a spreadsheet or a .csv file."):format(
                rows, rows == 1 and "row" or "rows"))
        end
    end)
    ER:Add(exportButton, UI.ROW + 2)
    UI.Tooltip(exportButton, "Export", "Addons can't write files: the CSV text goes into the box below to copy. Names follow the privacy setting (Team page). Other accounts only send summaries: their gold per day as account totals, their top 25 kills and top 10 killers.")
    local backupButton = UI.Button(s, COL_W, "Backup (for import)", function()
        local text = mod.BackupText()
        area.edit:SetText(text)
        area.edit:SetFocus()
        area.edit:HighlightText()
        estatus:SetText(("Backup of this account (%d characters). Copy it with Ctrl+A, Ctrl+C and keep it in a text file."):format(
            (function() local n = 0 for _ in pairs(mod.Store().chars) do n = n + 1 end return n end)()))
    end)
    EL:Add(backupButton, UI.ROW + 2)
    UI.Tooltip(backupButton, "Backup (for import)", "All statistics of this account (real names, gold per day, kills, deaths, quests) as one text, for another computer or a reinstalled client: paste it into this box there and click \"Import backup\".")
    local importButton = UI.Button(s, COL_W, "Import backup", function()
        local chars, days, quests = mod.ImportBackup(area.edit:GetText())
        if not chars then
            estatus:SetText("|cffff6666" .. days .. "|r")
            return
        end
        estatus:SetText(("Imported: %d new characters, %d days of gold, %d quests. Data recorded here was kept."):format(chars, days, quests))
        MMT.Print("Statistics backup imported: %d new characters, %d days of gold, %d quests.", chars, days, quests)
    end)
    ER:Add(importButton, UI.ROW + 2)
    UI.Tooltip(importButton, "Import backup", "Paste a backup (made with \"Backup (for import)\") into the box below first. It is merged into this account: what was recorded here stays, missing days and quests are added, kill counts take the higher number.")
    local ay = math.min(EL.y, ER.y)
    mod.exportAreaY = ay   -- debug / harness
    area:SetPoint("TOPLEFT", s, "TOPLEFT", 0, ay)
    estatus:SetPoint("TOPLEFT", area, "BOTTOMLEFT", 0, -4)
    s:HookScript("OnShow", function() escope.Refresh() end)

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
        elseif current == "quests" then
            DrawQuests()
        end
    end
    page:SetScript("OnShow", function() mod.Redraw() end)
    page.OnRefresh = function() mod.Redraw() end

    -- "Request update" left of the "Sync to team" button (bottom right)
    local request = UI.Button(page, 150, "Request update", function() mod.RequestUpdate() end)
    request:SetHeight(26)
    request:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -186, 2)
    request:SetFrameLevel(page:GetFrameLevel() + 10)
    UI.Tooltip(request, "Request update", "Asks every team member for their gold and kill statistics now (each answers out of combat, within about 20 seconds) and sends this account's too. Needs \"Share with the team\".")
    Show("gold")
end

-- /mmtstats and a key (key binding menu > MMT (Manage My Team) > Statistics) open the page
SLASH_MMTSTATS1 = "/mmtstats"
SlashCmdList.MMTSTATS = function() MMT.ToggleConfig("mod:Statistics") end
BINDING_HEADER_MMT_STATISTICS = "Statistics"
BINDING_NAME_MMT_STATISTICS = "Open / close Statistics"
function MMT_ToggleStatistics() if M.enabled then MMT.ToggleConfig("mod:Statistics") end end
