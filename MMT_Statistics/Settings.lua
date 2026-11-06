-- MMT Statistics: the module's page under MODULES, with the tabs Gold,
-- Kills, Quests, Leveling, Zones and Settings.

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

-- table with free columns, scrolling with the mouse wheel
--   cols: { { head, x = left edge | right = right edge, w = width }, ... }
--   rows: { cells = { text, ... }, grey = bool, tip = function(tooltip) end }
local function Grid(parent, cols, visible, width)
    width = width or PAGE_W
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, ROW_H * (visible + 1) + 4)
    local function Cell(owner, col, y, template)
        local l = UI.Label(owner, "", template)
        if col.right then
            l:SetPoint("TOPRIGHT", owner, "TOPLEFT", col.right, y)
            l:SetJustifyH("RIGHT")
        else
            l:SetPoint("TOPLEFT", owner, "TOPLEFT", col.x, y)
            l:SetJustifyH("LEFT")
        end
        l:SetWidth(col.w)
        l:SetWordWrap(false)
        return l
    end
    f.heads = {}
    for i, col in ipairs(cols) do
        local l = Cell(f, col, -3, "GameFontNormal")
        l:SetText(col[1])
        l:SetTextColor(A[1], A[2], A[3])
        f.heads[i] = l
    end
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, -ROW_H)
    line:SetWidth(width)
    f.list = H.List(f, width, visible, ROW_H, function(list, i)
        local row = CreateFrame("Frame", nil, list)
        H.RowBackground(row, i)
        row.cells = {}
        for c, col in ipairs(cols) do row.cells[c] = Cell(row, col, -4) end
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
        for c = 1, #cols do
            row.cells[c]:SetText(d.cells[c] or "")
            if d.grey then row.cells[c]:SetTextColor(0.55, 0.55, 0.55)
            elseif d.accent then row.cells[c]:SetTextColor(A[1], A[2], A[3])
            else row.cells[c]:SetTextColor(0.85, 0.85, 0.85) end
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

local function Num(n)
    if not n then return "" end
    n = math.floor(n + 0.5)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end
-- averages: one decimal below 10
local function Avg(n)
    if not n then return "" end
    if n < 10 and math.floor(n) ~= n then return ("%.1f"):format(n) end
    return Num(n)
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
    -- notice on the tabs whose numbers stay on this account
    local LOCAL_TABS = { kills = true, quests = true, leveling = true, zones = true }
    local NOTICE_H = 24
    local notice = CreateFrame("Frame", nil, page)
    notice:SetPoint("TOPLEFT", 0, -32)
    notice:SetSize(PAGE_W, NOTICE_H)
    UI.Fill(notice, 1, 0.82, 0, 0.10)
    UI.Border(notice, 1, 0.82, 0, 0.45)
    local noticeText = UI.Label(notice, "", "GameFontNormal")
    noticeText:SetPoint("LEFT", 10, 0)
    noticeText:SetPoint("RIGHT", -10, 0)
    noticeText:SetJustifyH("LEFT")
    noticeText:SetWordWrap(false)
    noticeText:SetTextColor(1, 0.82, 0)
    noticeText:SetText("Account / character statistics: kept for this account's characters only and not shared with the team.")
    local function Show(key)
        current = key
        notice:SetShown(LOCAL_TABS[key] == true)
        for k, p in pairs(panels) do p:SetShown(k == key) end
        for k, b in pairs(buttons) do
            if k == key then b.label:SetTextColor(A[1], A[2], A[3]) else b.label:SetTextColor(0.7, 0.7, 0.7) end
        end
        if key ~= "settings" then mod.RequestIfOld() end
        if mod.Redraw then mod.Redraw() end
    end
    local tabs = { { "gold", "Gold" }, { "kills", "Kills" }, { "quests", "Quests" }, { "leveling", "Leveling" },
        { "zones", "Zones" }, { "settings", "Settings" } }
    for i, t in ipairs(tabs) do
        local b = UI.Button(page, 108, t[2], function() Show(t[1]) end)
        b:SetPoint("TOPLEFT", (i - 1) * 116, 0)
        buttons[t[1]] = b
        local p = CreateFrame("Frame", nil, page)
        local shift = LOCAL_TABS[t[1]] and (NOTICE_H + 8) or 0
        p:SetPoint("TOPLEFT", 0, -32 - shift)
        p:SetSize(PAGE_W, 520 - shift)
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
    local kscope = UI.Dropdown(k, 300, "Show", function() return mod.CharChoices("This account") end,
        function() return M.db.killScope end, function(v) M.db.killScope = v; mod.Redraw() end)
    kscope:SetPoint("TOPLEFT", 0, 0)
    local ky = -(UI.ROW + 8)
    -- six boxes: NPCs | Rares | Dungeon Bosses | Big Baddies | Deaths / By Gravity | Critters
    local BOX_H, GAP = 54, 8
    local boxW = math.floor((PAGE_W - 5 * GAP) / 6)
    local kboxes = {}
    local function Box(i, key, label, colour, tip)
        local b = CreateFrame("Frame", nil, k)
        b:SetSize(boxW, BOX_H)
        b:SetPoint("TOPLEFT", k, "TOPLEFT", (i - 1) * (boxW + GAP), ky)
        b:SetFrameLevel(k:GetFrameLevel() + 5)
        UI.Fill(b, 1, 1, 1, 0.03)
        UI.Border(b, 1, 1, 1, 0.08)
        b.number = UI.Label(b, "0", "GameFontHighlightLarge")
        pcall(b.number.SetFont, b.number, STANDARD_TEXT_FONT, 22, "")
        b.number:SetPoint("TOP", 0, -8)
        b.number:SetTextColor(colour[1], colour[2], colour[3])
        b.label = UI.Label(b, label)
        b.label:SetPoint("TOP", b.number, "BOTTOM", 0, -3)
        b.label:SetTextColor(0.6, 0.6, 0.6)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tip, 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        kboxes[key] = b
        return b
    end
    Box(1, "all", "NPCs", { 1, 1, 1 }, "Every NPC killed.")
    Box(2, "rare", "Rares", { 0.75, 0.75, 1 }, "Rare and rare elite NPCs.")
    Box(3, "dboss", "Dungeon Bosses", { 1, 0.6, 0.2 }, "Bosses of dungeons: encounter bosses and NPCs with the game's boss flag inside a dungeon (raid bosses count as Big Baddies).")
    Box(4, "big", "Big Baddies", { 1, 0.3, 0.3 }, "Raid bosses, and NPCs with the game's boss flag outside instances: world bosses and skull-level (??) bosses.")
    -- deaths: split into two halves
    local dbox = CreateFrame("Frame", nil, k)
    dbox:SetSize(boxW, BOX_H)
    dbox:SetPoint("TOPLEFT", k, "TOPLEFT", 4 * (boxW + GAP), ky)
    dbox:SetFrameLevel(k:GetFrameLevel() + 5)
    UI.Fill(dbox, 1, 1, 1, 0.03)
    UI.Border(dbox, 1, 1, 1, 0.08)
    local split = dbox:CreateTexture(nil, "ARTWORK")
    split:SetColorTexture(1, 1, 1, 0.08)
    split:SetHeight(1)
    split:SetPoint("LEFT", 4, 0)
    split:SetPoint("RIGHT", -4, 0)
    local function Half(top, label)
        local n = UI.Label(dbox, "0", "GameFontHighlight")
        pcall(n.SetFont, n, STANDARD_TEXT_FONT, 15, "")
        n:SetPoint(top and "TOPLEFT" or "BOTTOMLEFT", 10, top and -6 or 6)
        local l = UI.Label(dbox, label)
        l:SetPoint("LEFT", n, "RIGHT", 6, 0)
        l:SetTextColor(0.6, 0.6, 0.6)
        return n
    end
    kboxes.deaths = { number = Half(true, "Deaths") }
    kboxes.deaths.number:SetTextColor(0.9, 0.9, 0.9)
    kboxes.gravity = { number = Half(false, "By Gravity") }
    kboxes.gravity.number:SetTextColor(0.6, 0.8, 1)
    dbox:EnableMouse(true)
    dbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Deaths", 1, 1, 1)
        GameTooltip:AddLine("Every death; \"By Gravity\": the ones right after a fall.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    dbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- critters: a smaller, playful box
    local cb = CreateFrame("Frame", nil, k)
    cb:SetSize(boxW, BOX_H - 10)
    cb:SetPoint("TOPLEFT", k, "TOPLEFT", 5 * (boxW + GAP), ky - 5)
    cb:SetFrameLevel(k:GetFrameLevel() + 5)
    UI.Fill(cb, 0.4, 1, 0.5, 0.06)
    UI.Border(cb, 0.4, 1, 0.5, 0.35)
    local sheep = cb:CreateTexture(nil, "ARTWORK")
    sheep:SetTexture("Interface\\Icons\\Spell_Nature_Polymorph")
    sheep:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    sheep:SetSize(26, 26)
    sheep:SetPoint("LEFT", 8, 0)
    sheep:SetRotation(math.rad(-12))
    local cn = UI.Label(cb, "0", "GameFontHighlight")
    pcall(cn.SetFont, cn, STANDARD_TEXT_FONT, 16, "")
    cn:SetPoint("TOPLEFT", sheep, "TOPRIGHT", 8, 2)
    cn:SetTextColor(0.5, 1, 0.55)
    local cl = UI.Label(cb, "cuddly kills")
    cl:SetPoint("TOPLEFT", cn, "BOTTOMLEFT", 0, -1)
    cl:SetTextColor(0.55, 0.75, 0.55)
    kboxes.critter = { number = cn }
    cb:EnableMouse(true)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Critters", 0.5, 1, 0.55)
        GameTooltip:AddLine("Rabbits, squirrels, toads... They had it coming.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- left: top kills by kind and zone, top killers
    local below = ky - BOX_H - 14
    local KL = UI.Column(k, 0, below, COL_W)
    local KIND_CHOICES = {
        { value = "ALL", text = "All kills" },
        { value = "rare", text = "Rares" },
        { value = "dboss", text = "Dungeon Bosses" },
        { value = "big", text = "Big Baddies" },
        { value = "critter", text = "Critters" },
    }
    local kkind = UI.Dropdown(k, COL_W, "Kills", KIND_CHOICES,
        function() return M.db.killKind end, function(v) M.db.killKind = v; mod.Redraw() end)
    KL:Add(kkind, UI.ROW + 2)
    local kzone = UI.Dropdown(k, COL_W, "Zone", function() return mod.KillZoneChoices(M.db.killScope) end,
        function() return M.db.killZone end, function(v) M.db.killZone = v; mod.Redraw() end)
    KL:Add(kzone, UI.ROW + 6)
    KL:Header("Top 10 kills")
    local top = RankList(k, COL_W, 10)
    KL:Add(top, 10 * 18 + 4)
    KL:Header("Top 3 killed by")
    local killers = RankList(k, COL_W, 3)
    KL:Add(killers, 3 * 18)

    -- right: the Dungeon Journal, a box of its own with a title like a page's
    local JROWS = 7
    local jbox = CreateFrame("Frame", nil, k)
    jbox:SetPoint("TOPLEFT", k, "TOPLEFT", COL2_X - 8, below)
    jbox:SetSize(COL_W + 16, 34 + (UI.ROW + 4) + 56 + ROW_H * (JROWS + 1) + 16)
    UI.Fill(jbox, A[1], A[2], A[3], 0.04)
    UI.Border(jbox, A[1], A[2], A[3], 0.30)
    local jicon = jbox:CreateTexture(nil, "ARTWORK")
    jicon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
    jicon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    jicon:SetSize(22, 22)
    jicon:SetPoint("TOPLEFT", 8, -7)
    local jtitle = UI.Label(jbox, "Dungeon Journal", "GameFontNormalLarge")
    jtitle:SetPoint("LEFT", jicon, "RIGHT", 8, 0)
    jtitle:SetTextColor(A[1], A[2], A[3])
    local jline = jbox:CreateTexture(nil, "ARTWORK")
    jline:SetColorTexture(A[1], A[2], A[3], 0.35)
    jline:SetHeight(1)
    jline:SetPoint("TOPLEFT", 8, -34)
    jline:SetPoint("TOPRIGHT", -8, -34)
    local KR = UI.Column(jbox, 8, -40, COL_W)
    local jinst = UI.Dropdown(jbox, COL_W, "Instance", function() return mod.JournalChoices(M.db.killScope) end,
        function() return mod.JournalInstance(M.db.killScope) end, function(v) mod.journalPick = v; mod.Redraw() end)
    KR:Add(jinst, UI.ROW + 4)
    local junique = UI.Label(jbox, "")
    KR:Add(junique, 16)
    local jvisits = UI.Label(jbox, "")
    jvisits:SetTextColor(0.6, 0.6, 0.6)
    KR:Add(jvisits, 16)
    local jkills = UI.Label(jbox, "")
    jkills:SetTextColor(0.6, 0.6, 0.6)
    KR:Add(jkills, 20)
    local journal = Grid(jbox, {
        { "Boss", x = 8, w = 180 },
        { "Killed", right = 262, w = 64 },
        { "Killed me", right = COL_W - 8, w = 70 },
    }, JROWS, COL_W)
    KR:Add(journal, ROW_H * (JROWS + 1) + 6)

    local function DrawKills()
        kscope.Refresh() kkind.Refresh() kzone.Refresh() jinst.Refresh()
        local scope = M.db.killScope
        local t = mod.KillTotals(scope)
        for key, b in pairs(kboxes) do b.number:SetText(Num(t[key] or 0)) end
        top:Show_(mod.TopKills(scope, M.db.killKind or "ALL", M.db.killZone or "ALL", "killDetail", 10), "No kills recorded yet.")
        killers:Show_(mod.TopKills(scope, "ALL", M.db.killZone or "ALL", "deathDetail", 3), "Nobody killed you yet.")
        local inst = mod.JournalInstance(scope)
        local j = inst and mod.Journal(scope, inst)
        local uniq = mod.UniqueInstances(scope)
        junique:SetText(("Total unique instances visited: |cffffffff%d|r"):format(uniq))
        if j then
            jvisits:SetText(j.visits > 0 and ("Visited %d %s, last on %s."):format(j.visits, j.visits == 1 and "time" or "times",
                date("%Y-%m-%d %H:%M", j.last)) or "No visits recorded.")
            jkills:SetText(("NPCs killed: |cffffffff%s|r   Dungeon bosses killed: |cffffffff%s|r"):format(Num(j.npcs), Num(j.bossKills)))
            local rows = {}
            for _, b in ipairs(j.bosses) do rows[#rows + 1] = { cells = { b.name, Num(b.kills), Num(b.deaths) } } end
            journal:Show_(rows, "No dungeon bosses recorded here yet.")
        else
            jvisits:SetText("No instance with kills recorded yet.")
            jkills:SetText("")
            journal:Show_({}, "")
        end
    end

    -- Quests -------------------------------------------------------------------
    local q = panels.quests
    local qc = UI.Column(q, 0, 0, PAGE_W)
    local qscope = UI.Dropdown(q, 300, "Show", function() return mod.CharChoices("This account") end,
        function() return M.db.questScope end, function(v) M.db.questScope = v; mod.Redraw() end)
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
        { x = 8, w = 104, head = "Completed" },
        { x = 116, w = 96, head = "Character" },
        { x = 216, w = 196, head = "Quest" },
        { right = 474, w = 58, head = "Quest Lvl" },
        { right = 536, w = 58, head = "Char Lvl" },
        { right = 600, w = 60, head = "XP" },
        { right = PAGE_W - 8, w = 86, head = "Money" },
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
            for _, it in ipairs(self.quest.items or {}) do
                local colour = it.q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.q]
                local r, g, b = 1, 1, 1
                if colour then r, g, b = colour.r, colour.g, colour.b end
                GameTooltip:AddDoubleLine((it.n or ("item " .. tostring(it.id))) .. (it.pick and " |cff888888(chosen)|r" or ""),
                    "x" .. (it.c or 1), r, g, b, 1, 1, 1)
            end
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
            if mod.InScope(M.db.questScope, key) then
                for id, rec in pairs(c.quests or {}) do
                    if rec.scan then
                        n.S = n.S + 1
                        if rec.st == "C" then n.SC = n.SC + 1 end
                    else
                        -- accepted = every quest taken: active, completed and abandoned ones
                        n.A = n.A + 1
                        if rec.st == "C" or rec.st == "X" then n[rec.st] = n[rec.st] + 1 end
                    end
                    if rec.st == "C" and rec.tc then
                        done[#done + 1] = { id = id, rec = rec, key = key, class = c.class }
                    end
                end
            end
        end
        for k, tile in pairs(tiles) do tile.number:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(n[k]) or tostring(n[k])) end
        tiles.A.tip = "Quests this character took while MMT tracked them: the ones still active in the quest log plus the completed and abandoned ones."
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
                row.quest = { id = e.id, name = name, cl = r.cl, items = r.items }
                row.cells[1]:SetText(date("%Y-%m-%d %H:%M", r.tc))
                row.cells[2]:SetText(mod.CharName(e.key, e.class))
                row.cells[3]:SetText(name)
                row.cells[4]:SetText(r.l and tostring(r.l) or "")
                row.cells[5]:SetText(r.cl and tostring(r.cl) or "")
                row.cells[6]:SetText(r.xp and (BreakUpLargeNumbers and BreakUpLargeNumbers(r.xp) or tostring(r.xp)) or "")
                row.cells[7]:SetText(r.cp and mod.Money(r.cp) or "")
                for c = 1, 7 do row.cells[c]:SetTextColor(0.8, 0.8, 0.8) end
                row.cells[3]:SetTextColor(1, 1, 1)
            end
        end
        qempty:SetShown(#done == 0)
    end

    -- Leveling -----------------------------------------------------------------
    local lvp = panels.leveling
    local lc = UI.Column(lvp, 0, 0, PAGE_W)
    local lscope = UI.Dropdown(lvp, 300, "Show", function() return mod.CharChoices("Average of account") end,
        function() return M.db.levelScope end, function(v) M.db.levelScope = v; mod.Redraw() end)
    lc:Add(lscope, UI.ROW + 8)
    local LEVEL_ROWS = 17
    local levelGrid = Grid(lvp, {
        { "Level", right = 44, w = 40 },
        { "Time to Level", x = 56, w = 100 },
        { "Date/Time leveled", x = 160, w = 122 },
        { "compl. Quests", right = 372, w = 88 },
        { "NPCs killed", right = 452, w = 76 },
        { "Deaths", right = 502, w = 46 },
        { "Instances", right = 572, w = 64 },
        { "Fav. Zone", x = 588, w = PAGE_W - 592 },
    }, LEVEL_ROWS)
    lc:Add(levelGrid, ROW_H * (LEVEL_ROWS + 1) + 10)
    local levelNote = lc:Note("")

    local function DrawLeveling()
        lscope.Refresh()
        local scope = M.db.levelScope or "CHAR"
        if scope ~= "CHAR" and scope ~= "ACCOUNT" and not (scope:sub(1, 5) == "char:" and mod.Store().chars[scope:sub(6)]) then
            scope = "CHAR"   -- an old choice (team / all accounts) or a character no longer here
        end
        local rows = {}
        -- first row: the sum of every row below (time, quests, kills, deaths, instances)
        local total = { t = 0, q = 0, k = 0, d = 0, i = 0, zones = {} }
        local function Count(t, q, k, d, i, z)
            total.t, total.q, total.k, total.d, total.i = total.t + (t or 0), total.q + (q or 0),
                total.k + (k or 0), total.d + (d or 0), total.i + (i or 0)
            if z and z ~= "" then total.zones[z] = (total.zones[z] or 0) + 1 end
        end
        local function TotalRow(average)
            local fav, favN
            for z, n in pairs(total.zones) do if not favN or n > favN then fav, favN = z, n end end
            local F = average and Avg or Num
            return { accent = true,
                cells = { "Total", mod.Duration(total.t), "", F(total.q), F(total.k), F(total.d), F(total.i), fav or "" },
                tip = function(t)
                    t:SetText("Total")
                    t:AddLine(average and "The sum of the averages below: what a character of this account takes up to the highest level listed."
                        or "The sum of every level below. Fav. Zone: the zone that was the favourite on the most levels.", 1, 1, 1, true)
                end }
        end
        if scope ~= "ACCOUNT" then
            levelGrid.heads[3]:SetText("Date/Time leveled")
            local key = scope == "CHAR" and (MMT.PlayerFull() or "") or scope:sub(6)
            local c = mod.Store().chars[key]
            for _, r in ipairs(c and mod.CharLevelRows(c, true, key) or {}) do
                if r.missing then
                    rows[#rows + 1] = {
                        cells = { tostring(r.L), "no data recorded", "(was addon disabled?)", "", "", "", "", "" },
                        grey = true,
                        tip = function(t)
                            t:SetText(("Level %d"):format(r.L))
                            t:AddLine("Nothing was recorded on this level: MMT, the Statistics module or its Leveling tracking was off (or not installed yet) then.", 1, 1, 1, true)
                        end,
                    }
                else
                rows[#rows + 1] = {
                    cells = { tostring(r.L), mod.Duration(r.t) .. ((r.partial or r.current or r.estimated) and " *" or ""),
                        r.done and ((r.estimated and "~ " or "") .. date("%Y-%m-%d %H:%M", r.done))
                            or (r.current and "(current)" or "(unknown)"),
                        Num(r.q), Num(r.k), Num(r.d), Num(r.i or 0), r.z or "" },
                    grey = r.current,
                    tip = (r.partial or r.current or r.estimated or r.open) and function(t)
                        t:SetText(("Level %d"):format(r.L))
                        if r.current then t:AddLine("The current level: still running.", 1, 1, 1, true) end
                        if r.estimated or r.open then t:AddLine("The level-up wasn't recorded (MMT or the Leveling tracking was off then): the time shown is the next level's start.", 1, 1, 1, true) end
                        if r.partial then t:AddLine("Tracking began during this level: the time and counts are only from then on.", 1, 1, 1, true) end
                    end or nil,
                }
                end
            end
            for _, r in ipairs(c and mod.CharLevelRows(c) or {}) do Count(r.t, r.q, r.k, r.d, r.i, r.z) end
            if #rows > 0 then table.insert(rows, 1, TotalRow(false)) end
            levelNote:SetText("Time counts while this character is logged in. * = the current level, tracking began during it, or its level-up wasn't recorded (~ time). Instances: entered on that level.")
        else
            levelGrid.heads[3]:SetText("Characters")
            for _, r in ipairs(mod.AverageLevelRows(scope)) do
                rows[#rows + 1] = {
                    cells = { tostring(r.L), r.t and mod.Duration(r.t) or "-", tostring(r.n), Avg(r.q), Avg(r.k), Avg(r.d), Avg(r.i), r.z or "" },
                }
                Count(r.t, r.q, r.k, r.d, r.i, r.z)
            end
            if #rows > 0 then table.insert(rows, 1, TotalRow(true)) end
            levelNote:SetText("Averages per level over this account's characters that have it; the time only over the ones that finished it (from its start).")
        end
        levelGrid:Show_(rows, scope ~= "ACCOUNT" and "No levels recorded yet for this character." or "No levels recorded yet.")
    end

    -- Zones / Instances ----------------------------------------------------------
    local zp = panels.zones
    local zscope = UI.Dropdown(zp, COL_W, "Show", function() return mod.CharChoices("This account") end,
        function() return M.db.zoneScope end, function(v) M.db.zoneScope = v; mod.Redraw() end)
    zscope:SetPoint("TOPLEFT", 0, 0)
    local zview = UI.Dropdown(zp, COL_W, "List", {
        { value = "ZONES", text = "Zones" },
        { value = "INSTANCES", text = "Instances" },
    }, function() return M.db.zoneView end, function(v) M.db.zoneView = v; mod.Redraw() end)
    zview:SetPoint("TOPLEFT", COL2_X, 0)
    local zy = -(UI.ROW + 8)
    local favTiles = {}
    for i, t in ipairs({ { "time", "favorite zone (time spent)" }, { "kills", "most NPC kills in" } }) do
        local tile = CreateFrame("Frame", nil, zp)
        local w = math.floor((PAGE_W - 12) / 2)
        tile:SetSize(w, 70)
        tile:SetPoint("TOPLEFT", zp, "TOPLEFT", (i - 1) * (w + 12), zy)
        UI.Fill(tile, 1, 1, 1, 0.03)
        UI.Border(tile, 1, 1, 1, 0.08)
        tile.value = UI.Label(tile, "-", "GameFontHighlightLarge")
        pcall(tile.value.SetFont, tile.value, STANDARD_TEXT_FONT, 20, "")
        tile.value:SetPoint("TOP", 0, -12)
        tile.value:SetWidth(w - 16)
        tile.value:SetWordWrap(false)
        tile.value:SetTextColor(A[1], A[2], A[3])
        tile.label = UI.Label(tile, t[2])
        tile.label:SetPoint("TOP", tile.value, "BOTTOM", 0, -6)
        tile.label:SetTextColor(0.6, 0.6, 0.6)
        favTiles[t[1]] = tile
    end
    zy = zy - 70 - 14
    local ZONE_ROWS = 15
    local zoneGrid = Grid(zp, {
        { "Zone Name", x = 8, w = 250 },
        { "Time Spent", right = 380, w = 110 },
        { "NPC kills", right = 470, w = 80 },
        { "Quests completed", right = 590, w = 110 },
        { "XP Gain", right = PAGE_W - 8, w = 90 },
    }, ZONE_ROWS)
    zoneGrid:SetPoint("TOPLEFT", 0, zy)
    local instGrid = Grid(zp, {
        { "Instance Name", x = 8, w = 116 },
        { "ID", right = 168, w = 38 },
        { "Lvl In", right = 214, w = 42 },
        { "Lvl Out", right = 264, w = 46 },
        { "Time Spent", right = 338, w = 70 },
        { "Kills", right = 380, w = 38 },
        { "Quests", right = 430, w = 46 },
        { "XP Gain", right = 498, w = 64 },
        { "XP/hr", right = 562, w = 60 },
        { "Money", right = PAGE_W - 8, w = 124 },
    }, ZONE_ROWS)
    instGrid:SetPoint("TOPLEFT", 0, zy)
    local zoneNote = UI.Label(zp, "")
    zoneNote:SetPoint("TOPLEFT", 0, zy - ROW_H * (ZONE_ROWS + 1) - 12)
    zoneNote:SetWidth(PAGE_W)
    zoneNote:SetJustifyH("LEFT")
    zoneNote:SetTextColor(0.6, 0.6, 0.6)

    local function DrawZones()
        zscope.Refresh()
        zview.Refresh()
        local me = MMT.PlayerFull()
        local zones, runs = {}, {}
        for key, c in pairs(mod.Store().chars) do
            if mod.InScope(M.db.zoneScope, key) then
                for key0, z in pairs(c.zones or {}) do
                    -- land zones by name (a zone read once without its map ID counts the same)
                    local zk = z.inst and key0 or ("name:" .. tostring(z.n))
                    local sum = zones[zk] or { n = z.n, inst = z.inst, t = 0, k = 0, q = 0, xp = 0 }
                    sum.t, sum.k, sum.q, sum.xp = sum.t + (z.t or 0), sum.k + (z.k or 0), sum.q + (z.q or 0), sum.xp + (z.xp or 0)
                    zones[zk] = sum
                end
                for _, r in ipairs(c.runs or {}) do runs[#runs + 1] = { r = r, key = key, class = c.class } end
            end
        end
        local favT, favK
        for _, z in pairs(zones) do
            if z.t > 0 and (not favT or z.t > favT.t) then favT = z end
            if z.k > 0 and (not favK or z.k > favK.k) then favK = z end
        end
        favTiles.time.value:SetText(favT and favT.n or "-")
        favTiles.kills.value:SetText(favK and favK.n or "-")
        local instances = M.db.zoneView == "INSTANCES"
        zoneGrid:SetShown(not instances)
        instGrid:SetShown(instances)
        if instances then
            -- without a readable copy ID (hidden inside instances on WoW: Forever)
            -- the runs of an instance are numbered in order: #1, #2, ...
            table.sort(runs, function(a, b) return (a.r.enter or 0) < (b.r.enter or 0) end)
            local count = {}
            for _, e in ipairs(runs) do
                local k = e.key .. ":" .. tostring(e.r.map)
                count[k] = (count[k] or 0) + 1
                e.nr = count[k]
            end
            table.sort(runs, function(a, b) return (a.r.enter or 0) > (b.r.enter or 0) end)
            local rows = {}
            for _, e in ipairs(runs) do
                local r = e.r
                local perHour = (r.t or 0) >= 60 and (r.xp or 0) / (r.t / 3600) or nil
                rows[#rows + 1] = {
                    cells = { r.n or ("Instance " .. tostring(r.map)), r.uid and tostring(r.uid) or ("#" .. e.nr),
                        r.lvIn and tostring(r.lvIn) or "",
                        (r.lvOut and not (r.leave == nil and e.key == me)) and tostring(r.lvOut)
                            or ((r.leave == nil and e.key == me) and (mod.LevelNow() .. "*") or ""),
                        mod.Clock(r.t),
                        Num(r.k), Num(r.q or 0), Num(r.xp), perHour and Num(perHour) or "-", mod.Money(r.cp or 0) },
                    tip = function(t)
                        t:SetText((r.n or "Instance") .. (r.zn and (" (" .. r.zn .. ")") or ""), 1, 1, 1)
                        local lvOut = r.lvOut
                        if r.leave == nil and e.key == me then lvOut = mod.LevelNow() end
                        t:AddDoubleLine("Entered:", date("%Y-%m-%d %H:%M", r.enter or 0) .. (r.lvIn and ("  (Level: %d)"):format(r.lvIn) or ""), 0.7, 0.7, 0.7, 1, 1, 1)
                        t:AddDoubleLine("Exit:", (r.leave and date("%Y-%m-%d %H:%M", r.leave) or "still inside")
                            .. (lvOut and ("  (Level: %d)"):format(lvOut) or ""), 0.7, 0.7, 0.7, 1, 1, 1)
                        local hours = (r.t or 0) / 3600
                        local function PerHour(v) return hours > 0 and v / hours or nil end
                        local xpH, cpH = PerHour(r.xp or 0), PerHour(r.cp or 0)
                        t:AddDoubleLine("XP gained:", Num(r.xp or 0) .. (xpH and ("  (%s / hr)"):format(Num(xpH)) or ""), 0.7, 0.7, 0.7, 1, 1, 1)
                        t:AddDoubleLine("Money gained:", mod.Money(r.cp or 0) .. (cpH and ("  (%s / hr)"):format(mod.Money(cpH)) or ""), 0.7, 0.7, 0.7, 1, 1, 1)
                        t:AddDoubleLine("Kills:", Num(r.k or 0), 0.7, 0.7, 0.7, 1, 1, 1)
                        t:AddDoubleLine("Quests completed:", Num(r.q or 0), 0.7, 0.7, 0.7, 1, 1, 1)
                        t:AddLine(" ")
                        t:AddLine(mod.CharName(e.key, e.class), 0.7, 0.7, 0.7)
                        -- this character's visits of this instance (all / in the last 60 minutes)
                        local all, hour = 0, 0
                        for _, x in ipairs(mod.Store().chars[e.key] and mod.Store().chars[e.key].runs or {}) do
                            if x.map == r.map then
                                all = all + 1
                                if (x.enter or 0) > time() - 3600 then hour = hour + 1 end
                            end
                        end
                        t:AddLine(("This character entered this instance %d %s (%d in last 60 minutes)."):format(
                            all, all == 1 and "time" or "times", hour), 0.7, 0.7, 0.7, true)
                    end,
                }
            end
            instGrid:Show_(rows, "No instance visits recorded yet.")
            zoneNote:SetText(("One row per visit; re-entering an instance asks whether it is the same one. XP includes quest rewards. %s"):format(mod.HourText()))
        else
            local list = {}
            for _, z in pairs(zones) do if not z.inst then list[#list + 1] = z end end
            table.sort(list, function(a, b) if a.t ~= b.t then return a.t > b.t end return (a.n or "") < (b.n or "") end)
            local rows = {}
            for _, z in ipairs(list) do
                rows[#rows + 1] = { cells = { z.n or "?", mod.Clock(z.t), Num(z.k), Num(z.q), Num(z.xp) } }
            end
            zoneGrid:Show_(rows, "No zones recorded yet.")
            zoneNote:SetText("Main zones only (a town counts for its zone). Time in hh:mm:ss while logged in; XP includes quest rewards.")
        end
    end

    -- Settings -----------------------------------------------------------------
    local s = panels.settings
    local SL = UI.Column(s, 0, 0, COL_W)
    SL:Header("Tracking")
    SL:Check("Track gold", function() return M.db.trackGold end, function(v) M.db.trackGold = v; mod.RecordGold() end,
        "Records every character's gold after login and on every change: one record per day, kept for 60 days. Saved per account, not per profile.")
    SL:Check("Track kills and deaths", function() return M.db.trackKills end, function(v) M.db.trackKills = v end)
    SL:Check("Track leveling, zones and instances", function() return M.db.trackLeveling end, function(v) M.db.trackLeveling = v end,
        "Time played per level, zone and instance copy, with the quests, kills, deaths and experience there. For the Leveling and Zones tabs.")
    SL:Check("Ask if a re-entered instance is the same", function() return M.db.askSameInstance ~= false end,
        function(v) M.db.askSameInstance = v end,
        "Entering an instance you left within the last 3 hours (no reset since) asks whether it is the same instance as before; \"Same instance\" adds the visit to the earlier row. Off: every entry is a new row. (The game hides the instance ID from addons.)")
    SL:Check("Chat notes about instances", function() return M.db.instanceNotes ~= false end,
        function(v) M.db.instanceNotes = v end,
        "On entering an instance: new or the same one, its visit number, and how many instances this account entered in the last hour (the game allows 5 per hour).")
    SL:Check("Track quests", function() return M.db.trackQuests end, function(v) M.db.trackQuests = v end,
        "Records the quests each character accepts, completes (with its level, the experience and the money of the reward) and abandons. For the export (Quests). Not sent to the team.")
    SL:Check("Share with the team", function() return M.db.share end, function(v) M.db.share = v; if v then mod.SendNow() end end,
        "Sends this account's gold (per character and per day) to the team and keeps theirs, for the Gold tab. Kills, quests, levels and zones stay on this account. Never in combat, at most as often as set below, and with the lowest priority.")
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
    UI.Tooltip(exportButton, "Export", "Addons can't write files: the CSV text goes into the box below to copy. Names follow the privacy setting (Team page). Other accounts only send their gold (per character, and per day as account totals); kills, quests, levels and zones are this account's only.")
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
            DrawKills()
        elseif current == "quests" then
            DrawQuests()
        elseif current == "leveling" then
            DrawLeveling()
        elseif current == "zones" then
            DrawZones()
        end
    end
    page:SetScript("OnShow", function() mod.Redraw() end)
    page.OnRefresh = function() mod.Redraw() end

    -- "Request update" left of the "Sync to team" button (bottom right)
    local request = UI.Button(page, 150, "Request update", function() mod.RequestUpdate() end)
    request:SetHeight(26)
    request:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -186, 2)
    request:SetFrameLevel(page:GetFrameLevel() + 10)
    UI.Tooltip(request, "Request update", "Asks every team member for their gold statistics now (each answers out of combat, within about 20 seconds) and sends this account's too. Needs \"Share with the team\".")
    Show("gold")
end

-- /mmtstats and a key (key binding menu > MMT (Manage My Team) > Statistics) open the page
SLASH_MMTSTATS1 = "/mmtstats"
SlashCmdList.MMTSTATS = function() MMT.ToggleConfig("mod:Statistics") end
BINDING_HEADER_MMT_STATISTICS = "Statistics"
BINDING_NAME_MMT_STATISTICS = "Open / close Statistics"
function MMT_ToggleStatistics() if M.enabled then MMT.ToggleConfig("mod:Statistics") end end
