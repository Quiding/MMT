-- MMT Loot Distribution: settings page (under MODULES in /mmt) and debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X, PAGE_W = H.COL_W, H.COL2_X, H.PAGE_W
local StatusLine = H.StatusLine

-- a checkbox whose label may take two lines
local function LongCheck(col, parent, width, text, get, set, tip)
    local cb = UI.Check(parent, width, text, get, set, tip)
    cb:SetHeight(UI.ROW * 2 - 6)
    cb.label:SetWordWrap(true)
    cb.label:SetMaxLines(2)
    col:Add(cb, UI.ROW * 2 - 2)
    return cb
end

local function Opt(key)
    return function() return M.db[key] end,
           function(v) M.db[key] = v end
end

M.Page = function(_, page)
    local status
    local root = page
    local Tile, TILE_W, X2 = H.Tile, H.TILE_W, H.TILE_W + H.TILE_GAP
    local INTRO = H.Intro(page, "Sets the loot method whenever one of your characters leads the group, hands out loot by your roles as master looter, and highlights what you can gather.")
    local panels, _, PANEL_H = H.TabStrip(page, INTRO, {
        { "loot", "Loot", "INV_Misc_Bag_10" },
        { "sparkles", "Sparkles", "INV_Misc_Herb_10" },
        { "never", "Never Loot", "INV_Misc_Bone_HumanSkull_01" },
        { "dejunk", "Dejunk", "INV_Misc_Gear_01" },
    }, H.SYNC_RESERVE)
    local SparklesTab = mod.SparklesTab
    page = panels.loot
    local TOP = 0
    local TOP_H, BOTTOM_H = 296, 148
    local Y2 = TOP - TOP_H - 8

    -- Loot Method (top left) ----------------------------------------------------------------
    local lt, L = Tile(page, 0, TOP, TILE_W, TOP_H, "Loot Method", "Interface\\Icons\\INV_Misc_Bag_10")
    local gog, sog = Opt("outsiderGroup")
    L:Check("Return to Group Loot when outsiders join", gog, sog,
        "While a player who isn't in your team list is in the group, the loot method is Group Loot with the threshold Uncommon. When they leave, the method and threshold below are set again.")
    local gkr, skr = Opt("keepRaid")
    L:Check("Keep loot settings in raid, even with outsiders", gkr, skr,
        "In a raid group the method and threshold below stay, also while players outside the team are in it (overrides \"Return to Group Loot when outsiders join\" there). In a party the option above applies as usual.")
    local ga, sa = Opt("autoMethod")
    L:Check("Set loot method automatically", ga, sa,
        "When a group forms or one of your team characters becomes leader, that character sets the method and threshold below. Only the group leader can change loot settings.")
    local gm, sm = Opt("method")
    L:Cycle("Method", {
        { value = "freeforall", text = "Free for All" },
        { value = "roundrobin", text = "Round Robin" },
        { value = "master", text = "Master Looter" },
    }, gm, sm)
    local qualities = {}
    for q = 0, 5 do qualities[#qualities + 1] = { value = q, text = MMT.QualityName(q) } end
    local gt, st = Opt("threshold")
    L:Cycle("Threshold", qualities, gt, st)
    local gl, sl = Opt("looter")
    local looter = L:Cycle("Master looter", function()
        local l = { { value = "LEADER", text = "Group leader" } }
        for _, key in ipairs(MMT.SortedMembers()) do l[#l + 1] = { value = key, text = MMT.FirstName(key) } end
        return l
    end, gl, sl)
    MMT.HoverMember(looter, function() return M.db.looter ~= "LEADER" and M.db.looter or nil end)
    L:Space(4)
    L:Button("Apply now", function()
        local ok, err = mod.ApplyLootSettings(true)
        status.Show_(ok and "Loot settings applied." or err, not ok)
    end)
    status = StatusLine(lt)
    status:SetWidth(TILE_W - 16)
    L:Add(status, 20)
    local current = L:Note("")

    -- Passing on Loot (bottom left) ------------------------------------------------------------
    _, L = Tile(page, 0, Y2, TILE_W, BOTTOM_H, "Passing on Loot", "Interface\\Icons\\Ability_Rogue_Sprint")
    local gp, sp = Opt("autoPass")
    L:Check("Automatically pass on loot rolls", gp, sp,
        "With Group Loot or Need before Greed, every character passes on its rolls by itself, except the leader chosen below, who rolls as usual. Set it on every client.")
    local go, so = Opt("optOut")
    L:Check("Enable 'Pass on Loot' while in a group", go, so,
        "Switches on the game's \"Pass on Loot\" for every character in a group except the leader chosen below, so they don't get loot (rolls and Round Robin). Switched off again when the character leaves the group or becomes the leader. Set it on every client.")
    local ge, se = Opt("passExcept")
    L:Cycle("Unless I'm the", {
        { value = "GROUP", text = "Group leader" },
        { value = "FTL", text = "FTL leader (character you play)" },
    }, ge, se)
    local goo, soo = Opt("optOutOutsider")
    L:Check("Do not 'Pass on Loot' with outsider in group", goo, soo,
        "While a player outside the team is in the group, \"Pass on Loot\" stays off on every character, so each one gets its own share of the loot. It comes back on when the outsider leaves. Set it on every client.")

    -- Master Loot by Roles (top right) ----------------------------------------------------------
    local _, R = Tile(page, X2, TOP, TILE_W, TOP_H + 8 + BOTTOM_H, "Master Loot by Roles", "Interface\\Icons\\INV_Misc_Coin_02")
    local masterOnly = {}
    local gr, sr = Opt("byRoles")
    masterOnly[#masterOnly + 1] = R:Check("Give items by roles", gr, sr,
        "As master looter, items at or above the threshold go to the team member whose roles want them (see Roles). Several members with that role: the first one in team order who has room.")
    local gmr, smr = Opt("multiRole")
    masterOnly[#masterOnly + 1] = R:Cycle("Several have the role", {
        { value = "FILL", text = "Fill up by team order" },
        { value = "RR", text = "Round robin" },
        { value = "ML", text = "Prioritize Master Looter" },
    }, gmr, smr)
    UI.Tooltip(masterOnly[#masterOnly], "Several have the role",
        "Fill up by team order: the first of them in team order gets everything until their bags are full (keeping the free slots below), then the next. Round robin: they get the items in turns. Prioritize Master Looter: when the master looter has the role too, it gets the item regardless of team order; the others (in team order) only when its bags are full.")
    local gnr, snr = Opt("noRoom")
    masterOnly[#masterOnly + 1] = R:Cycle("Role members have no room", {
        { value = "LEAVE", text = "Leave for manual" },
        { value = "RR", text = "Next team member with room" },
        { value = "SELF", text = "Give to master looter" },
    }, gnr, snr)
    UI.Tooltip(masterOnly[#masterOnly], "Role members have no room",
        "When a role wants the item but none of its members has room: leave it in the loot window, give it to the next team member with room (round robin, keeping the free slots), or to the master looter. Quest items are handled by their own round robin.")
    local gres, sres = Opt("reserve")
    masterOnly[#masterOnly + 1] = R:Slider("Keep free bag slots", 0, 20, 1, gres, sres)
    local fullCheck = LongCheck(R, R.parent, TILE_W - 16, "Destroy the least valued item, when free bag slot-limit is reached", function() return M.db.dejunkFull end,
        function(v) M.db.dejunkFull = v and true or false MMT.Refresh() end,
        "When a character is down to the free bag slots above, its least valuable item is destroyed during its next key press or click (the game only allows destroying on a key press or click), one per press, until it is above the limit again. Works for every character, not only as master looter.\nWhat may go is set in the Dejunk tab (quality limit, Never / Always destroy roles); the same option is there too.")
    local gu, su = Opt("unassigned")
    masterOnly[#masterOnly + 1] = R:Cycle("No role wants it", {
        { value = "LEAVE", text = "Leave for manual" },
        { value = "SELF", text = "Give to master looter" },
        { value = "RR", text = "Round robin to the team" },
    }, gu, su)
    local grr, srr = Opt("rrNotice")
    masterOnly[#masterOnly + 1] = R:Check("Say so in chat (round robin)", grr, srr,
        "Prints the items no role wants and where they went (only for you), e.g. \"Given [Item1], [Item2] to <Name1> and [Item3] to <Name2> (no Role; Rule: RR)\". Round robin keeps the free bag slots above; quest items are never part of it.")
    local grep, srep = Opt("report")
    masterOnly[#masterOnly + 1] = R:Check("Report in chat", grep, srep, "Prints the items given and the loot settings that were applied (only for you). Items are collected for 5 seconds and printed together, one line per role (\"Given [Item1], [Item2] to <Name> (Role)\"), per quest item (\"Quest Item: [Item] to <Name1>x2 and <Name2>x1\") and for items without a role. RR = round robin, Fill Up = by team order, ML prio = master looter first.")
    local gbop, sbop = Opt("bopRoles")
    masterOnly[#masterOnly + 1] = R:Check("Bind on Pickup on a role's item list", gbop, sbop,
        "A Bind on Pickup item that a role lists by name (Roles > Items, e.g. Corrupted Soul Shard) goes to that role's members like other loot. Only exact items count: a quality, item group or class rule never takes a Bind on Pickup item. With no member of the role here with room, it is posted in group chat as usual.\n\nOther Bind on Pickup items are never given out or looted: they are posted in group chat, and the master looter assigns them by hand. Items without loaded item data are left alone, too.")
    local hint = R:Note("")

    R:Header("Quest items")
    local gq, sq = Opt("questRR")
    masterOnly[#masterOnly + 1] = R:Check("Auto-Round Robin quest items", gq, sq,
        "As master looter, quest items go to the team members in turns, in team order. Only characters the game offers for the item (on the quest and able to receive it) get a turn. Turns are kept per item, so drops spread evenly. The free bag slots setting doesn't apply: quest items are given even into the last slot.")
    local gl, sl = Opt("questMLLast")
    masterOnly[#masterOnly + 1] = R:Check("Master looter's turn last", gl, sl,
        "In the quest item turns the master looter comes after everyone else, so the first drop of an item goes to the next team member instead of into the master looter's bags. Off: team order, the master looter first when it leads the team list.")
    local gqn, sqn = Opt("questNobody")
    masterOnly[#masterOnly + 1] = R:Cycle("Quest item nobody needs", {
        { value = "LOOT", text = "Hand out like other loot" },
        { value = "LEAVE", text = "Leave for manual" },
    }, gqn, sqn)
    UI.Tooltip(masterOnly[#masterOnly], "Quest item nobody needs",
        "A quest item whose objective is already done for every team member (e.g. Un'Goro Soil once everyone has enough): hand it out like any other item - its role, else \"No role wants it\" - or leave it in the loot window.")
    local gqc, sqc = Opt("questCache")
    masterOnly[#masterOnly + 1] = R:Check("Speed up assignment by caching", gqc, sqc,
        "Enabling this option should speed up automatic loot distribution for quest items and for members with full bags.\nMMT will snapshot the status of quest items per member regularly outside of looting, instead of asking the team on every looting about the quest status.\nMembers with full bags also report which of their stacks can still take items whenever their bags change, so MMT doesn't have to ask them while looting.\nDisable it if you experience issues looting quest items or with full bags.")

    local sparklesRefresh = SparklesTab(panels.sparkles, PANEL_H)
    local neverRefresh = mod.NeverLootTab(panels.never, PANEL_H, root)
    local dejunkRefresh = mod.DejunkTab(panels.dejunk, PANEL_H)
    page = root
    page.OnRefresh = function()
        sparklesRefresh()
        neverRefresh()
        dejunkRefresh()
        fullCheck.Refresh()
        local method, partyIndex = mod.GetMethod()
        local text = IsInGroup() and ("Current: " .. (mod.METHOD_TEXT[method] or tostring(method)))
            or "Not in a group."
        if IsInGroup() and method and method ~= "freeforall" then
            local t = mod.GetThreshold()
            if t then text = text .. ", from " .. MMT.QualityName(t) end
        end
        if IsInGroup() and method == "master" then
            text = text .. (mod.IsMasterLooter() and " (you are master looter)" or "")
        end
        current:SetText(text)
        local isMaster = M.db.method == "master"
        for _, w in ipairs(masterOnly) do w:SetAlpha(isMaster and 1 or 0.4) end
        looter:SetAlpha(isMaster and 1 or 0.4)
        local first = {}
        for _, c in ipairs(mod.ActiveChoosers()) do first[#first + 1] = c.title or c.name end
        hint:SetText(not isMaster and "These options only apply with Master Looter."
            or #first > 0 and ("Picked first by " .. table.concat(first, ", ") .. "; what it leaves goes by the rules above.")
            or "")
    end
    M:On("PARTY_LOOT_METHOD_CHANGED", function() if page:IsVisible() then page.OnRefresh() end end)
end

-- Never Loot tab: the Exclusion List's "in Loot" items, then the options of
-- the loot skips other addons registered (MMT.RegisterLootSkip)
function mod.NeverLootTab(panel, PANEL_H, root)
    local Tile, TILE_W = H.Tile, H.TILE_W
    local nt, N = Tile(panel, 0, 0, TILE_W, PANEL_H, "Never Loot", "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    N:Note("As master looter, these items are left on the corpse: not handed out and not looted. It costs no loot time: each item is only looked up once while the loot window is gone through anyway.")
    N:Space(4)
    local count = N:Note("")
    N:Button("Never Loot List", function()
        MMT.OpenExclusionList(root:GetParent(), "loot")
    end)
    N:Note("Drop items on the list (or shift-click them in). It is part of MMT's Exclusion List: \"Show Trade / Mail too\" in the window shows its trade and mail ticks as well.")
    local tipCheck = N:Check("Show it on item tooltips", function() return M.db.skipTip end,
        function(v) M.db.skipTip = v end,
        "Item tooltips say when the team never loots the item, and why (the list or an option below). With \"Loot anyway when worth at least\" they show its worth too, or \"looted anyway\" when it is worth enough (the stack in the bag or loot slot counts, or a full stack with \"Count a full stack\").")
    local opts = {}   -- { check, usable }
    for _, s in ipairs(mod.skips) do
        -- an option can hide itself (e.g. its addon isn't installed); no options left: no header
        local shown = {}
        for _, o in ipairs(type(s.options) == "table" and s.options or {}) do
            local ok, show = true, true
            if o.shown then ok, show = pcall(o.shown) end
            if ok and show then shown[#shown + 1] = o end
        end
        if #shown > 0 then
            N:Header(s.title or s.name)
            for _, o in ipairs(shown) do
                local cb = N:Check(o.text or "?", function() return o.get and o.get() end,
                    function(v)
                        if o.usable and not o.usable() then return end
                        if o.set then o.set(v) end
                    end, o.tip)
                opts[#opts + 1] = { check = cb, usable = o.usable, text = o.text, tip = o.tip }
            end
        end
    end
    N:Header("Valuable items")
    local worthCheck = N:Check("Loot anyway when worth at least", function() return M.db.worthOn end,
        function(v) M.db.worthOn = v end,
        "An item that the rules above would leave on the corpse (the Never Loot List and every option above) is handed out as usual when its vendor sell price, times how many are in the loot slot, reaches this amount.\nItems whose data the game hasn't loaded yet have no price: they stay on the corpse.")
    -- gold / silver / copper boxes
    local money = CreateFrame("Frame", nil, nt)
    money:SetSize(TILE_W - 16, UI.ROW)
    local boxes = {}
    local function Save()
        local g = tonumber(boxes[1]:GetText()) or 0
        local s = math.min(99, tonumber(boxes[2]:GetText()) or 0)
        local c = math.min(99, tonumber(boxes[3]:GetText()) or 0)
        M.db.worthMin = g * 10000 + s * 100 + c
    end
    local x = 22
    for i, u in ipairs({ { 5, 56, "Interface\\MoneyFrame\\UI-GoldIcon" }, { 2, 34, "Interface\\MoneyFrame\\UI-SilverIcon" },
            { 2, 34, "Interface\\MoneyFrame\\UI-CopperIcon" } }) do
        local e = UI.EditBox(money, u[2], "0")
        e:SetNumeric(true)
        e:SetMaxLetters(u[1])
        e:SetPoint("LEFT", x, 0)
        e:SetScript("OnTextChanged", function(self, byUser)
            self.UpdatePlaceholder()
            if byUser then Save() end
        end)
        e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        e:SetScript("OnEditFocusLost", function(self) self.UpdatePlaceholder() Save() end)
        local icon = money:CreateTexture(nil, "ARTWORK")
        icon:SetSize(13, 13)
        icon:SetTexture(u[3])
        icon:SetPoint("LEFT", e, "RIGHT", 3, 0)
        UI.Tooltip(e, "Worth at least", "Vendor sell price times the count in the loot slot. Enter the amount in gold, silver and copper.")
        boxes[i] = e
        x = x + u[2] + 22
    end
    N:Add(money, UI.ROW + 4)
    local stackCheck = N:Check("Count a full stack for stackable items", function() return M.db.worthStack end,
        function(v) M.db.worthStack = v end,
        "For items that stack (cloth, herbs, potions, ...), the price of a full stack counts instead of how many dropped: 1 Linen Cloth that sells for 10 copper counts as a stack of 20, 2 silver.")
    N:Space(6)
    N:Note("Only items Loot Distribution hands out are covered: with the threshold Poor that is every item. Items below the threshold are picked up by the game's auto loot before any addon sees them, and gathering is never master loot.")

    return function()
        local v = M.db.worthMin or 0
        local parts = { math.floor(v / 10000), math.floor(v / 100) % 100, v % 100 }
        for i, e in ipairs(boxes) do
            if not e:HasFocus() then e:SetText(parts[i] > 0 and tostring(parts[i]) or "") e.UpdatePlaceholder() end
        end
        worthCheck.Refresh()
        stackCheck.Refresh()
        tipCheck.Refresh()
        UI.SetActive(money, M.db.worthOn and true or false)
        UI.SetActive(stackCheck, M.db.worthOn and true or false)
        local n = 0
        for _, e in ipairs(MMT.db.exclusions or {}) do if e.loot then n = n + 1 end end
        count:SetText(n == 0 and "|cff999999No items on the list yet.|r"
            or ("|cffffffff%d|r item%s on the list."):format(n, n == 1 and "" or "s"))
        for _, o in ipairs(opts) do
            local ok, why = true, nil
            if o.usable then
                local okCall, a, b = pcall(o.usable)
                ok, why = okCall and a and true or false, okCall and b or nil
            end
            UI.SetActive(o.check, ok)
            if o.text then UI.Tooltip(o.check, o.text, ok and o.tip or ((o.tip and (o.tip .. "\n\n") or "") .. "|cffff8040" .. tostring(why or "Not available.") .. "|r")) end
            o.check.Refresh()
        end
    end
end

-- Dejunk tab: destroying (left), Never / Always destroy roles (right)
function mod.DejunkTab(panel, PANEL_H)
    local Tile, TILE_W, X2 = H.Tile, H.TILE_W, H.TILE_W + H.TILE_GAP
    local lt, L = Tile(panel, 0, 0, TILE_W, PANEL_H, "Destroying Items", "Interface\\Icons\\INV_Misc_Gear_01")
    L:Note("The game only lets addons destroy an item during a real key press or click, one item per press. MMT destroys without the game's confirmation popup, during your next key presses or clicks (moving, clicking in the world, ...).")
    local full = LongCheck(L, lt, TILE_W - 16, "Destroy the least valued item, when free bag slot-limit is reached", function() return M.db.dejunkFull end,
        function(v) M.db.dejunkFull = v and true or false MMT.Refresh() end,
        "Same option as in the Loot tab. At the free bag slots kept there (\"Keep free bag slots\"), the least valuable item that may go is destroyed during the next key press or click, one per press, until the bags are above the limit again.")
    local limit = L:Note("")
    local qualities = {}
    for q = 0, 4 do qualities[#qualities + 1] = { value = q, text = MMT.QualityName(q) } end
    local qual = L:Cycle("Never destroy above", qualities, function() return M.db.dejunkMaxQuality or 1 end,
        function(v) M.db.dejunkMaxQuality = v end)
    UI.Tooltip(qual, "Never destroy above", "Items of a better quality are never destroyed, unless an \"Always destroy\" role lists them. Quest items and items without a sell price are never destroyed either.")
    local team = L:Check("Destroy the same item on the team", function() return M.db.dejunkTeam end,
        function(v) M.db.dejunkTeam = v and true or false end,
        "When you destroy an item yourself (drag it out of the bags), MMT asks whether the team should destroy it too. If yes, every team member destroys all its stacks of it during its next key presses or clicks (broadcast your keys with ISBoxer and they go as you move). A member only does so with this option on. \"Never destroy\" roles still protect an item.")
    local chat = L:Check("Say so in chat", function() return M.db.dejunkChat ~= false end,
        function(v) M.db.dejunkChat = v and true or false end, "Prints what was destroyed and why (only for you).")
    L:Header("Destroy now")
    L:Button("Destroy the cheapest item", function() mod.DejunkNow() end)
    local keyRow = CreateFrame("Frame", nil, lt)
    keyRow:SetSize(TILE_W - 16, UI.ROW)
    local keyLabel = UI.Label(keyRow, "Key binding:")
    keyLabel:SetPoint("LEFT", 0, 0)
    local keyButton = UI.KeyBind(keyRow, 140, "MMT_DEJUNK")
    keyButton:SetPoint("LEFT", keyLabel, "RIGHT", 8, 0)
    UI.Tooltip(keyButton, "Destroy the cheapest item", "Key binding (also in the game's Key Bindings > MMT). Click, then press a key; right-click clears it. An item of an \"Always destroy\" role goes first.")
    L:Add(keyRow, UI.ROW + 4)
    local nextLine = L:Note("")

    local rt, R = Tile(panel, X2, 0, TILE_W, PANEL_H, "Never / Always Destroy", "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    R:Note("Pick roles: their item rules (Roles > Items) say which items count. Several roles can be picked.")
    local MAX, ROWS2 = 10, 5   -- two columns of role checks per list
    local half = math.floor((TILE_W - 16) / 2)
    local function RoleChecks(field)
        local checks = {}
        for r = 1, ROWS2 do
            local row = CreateFrame("Frame", nil, rt)
            row:SetSize(TILE_W - 16, UI.ROW)
            for c = 1, 2 do
                local cb
                cb = UI.Check(row, half - 4, "", function() return cb.role and M.db[field][cb.role] and true or false end,
                    function(v) if cb.role then M.db[field][cb.role] = v and true or nil end end)
                cb:SetPoint("LEFT", (c - 1) * half, 0)
                checks[#checks + 1] = cb
            end
            R:Add(row, UI.ROW)
        end
        local more = R:Note("")
        return checks, more
    end
    R:Header("Never destroy")
    local neverChecks, neverMore = RoleChecks("dejunkNever")
    R:Header("Always destroy")
    local alwaysChecks, alwaysMore = RoleChecks("dejunkAlways")
    local looted = R:Check("Right after looting", function() return M.db.dejunkAlwaysLooted end,
        function(v) M.db.dejunkAlwaysLooted = v and true or false end,
        "Items of these roles are destroyed during the next key presses or clicks after they land in the bags. Off: only with the button / key or at the free bag slot limit, where they always go first.")
    local noRoles = R:Note("")

    local function Fill(checks, more, field)
        local names = MMT.SortedRoleNames()
        for i, cb in ipairs(checks) do
            local name = names[i]
            cb.role = name
            cb:SetShown(name ~= nil)
            if name then
                if cb.label then cb.label:SetText(name) end
                cb.Refresh()
            end
        end
        more:SetText(#names > MAX and ("|cff999999+%d more roles (only the first %d can be picked here)|r"):format(#names - MAX, MAX) or "")
        for role in pairs(M.db[field]) do if not MMT.db.roles[role] then M.db[field][role] = nil end end
    end
    return function()
        full.Refresh() team.Refresh() chat.Refresh() looted.Refresh()
        limit:SetText(("|cff999999Limit: %d free bag slot(s) (\"Keep free bag slots\", Loot tab).|r"):format(M.db.reserve or 0))
        Fill(neverChecks, neverMore, "dejunkNever")
        Fill(alwaysChecks, alwaysMore, "dejunkAlways")
        noRoles:SetText(#MMT.SortedRoleNames() == 0 and "|cff999999No roles yet: make them in Roles.|r" or "")
        local item, value = mod.DejunkCandidate()
        nextLine:SetText(item and ("Next: %s  |cff999999(%s)|r"):format(tostring(item.link), mod.MoneyText and mod.MoneyText(value) or (GetCoinTextureString and GetCoinTextureString(value or 0)) or tostring(value))
            or "|cff999999Nothing to destroy right now.|r")
    end
end

-- Sparkles tab: what sparkles (left), how it looks (right)
function mod.SparklesTab(panel, PANEL_H)
    local Tile, TILE_W, X2 = H.Tile, H.TILE_W, H.TILE_W + H.TILE_GAP
    local S = mod.Sparkles
    local function Set(key) return function(v) M.db[key] = v S.Update() MMT.Refresh() end end
    local dep = {}

    local wt, W = Tile(panel, 0, 0, TILE_W, PANEL_H, "Highlight in the World", "Interface\\Icons\\INV_Misc_Herb_10")
    W:Check("Sparkles", function() return M.db.sparkles end, function(v)
            local function done() MMT.Refresh() end
            if v then S.SwitchOn(done) else S.SwitchOff(done) end
        end,
        "Highlights the herb, ore vein, corpse or object right in front of you, as long as you have the skill to gather it.\nThe game only tells addons about the one thing the interact key would pick (close by, in front of you), so only that one is highlighted, not everything around you.\n|cffffd100Switches on (out of combat) the game's \"Enable Interact Key\"|r (Options > Controls; switching Sparkles off asks whether it goes off too), the interact target's nameplate and icon, and a reach of 15 yards all around you; those are put back as they were when this is off.")
    local mark = H.Mark(wt)
    local syncDrop = W:Cycle("Sync-Behaviour", {
        { value = "LEADER", text = "Only on Group Leader" },
        { value = "TEAM", text = "Enable on entire team" },
    }, function() return M.db.sparkleSync or "LEADER" end, function(v)
        M.db.sparkleSync = v S.Update() MMT.Refresh()
    end)
    UI.Tooltip(syncDrop, "Sync-Behaviour",
        "It is recommended to only enable Sparkles on the main character, to reduce unintended behavior of the background windows.\n\n"
        .. "Select \"Only on Group Leader\" to keep it only on the leader (FTL leader > Group leader)\n"
        .. "Select \"Enable on entire team\" to see Sparkles for the rest of the team.")
    local NOT_HERE = "|cffff8040Not active on this character: Sparkles only shows on the team's leader (FTL leader, else group leader).|r"
    local leaderNote = W:Note(NOT_HERE)
    W:Space(4)
    W:Check("Herbs (Herbalism)", function() return M.db.sparkleHerbs end, Set("sparkleHerbs"))
    W:Check("Ore veins (Mining)", function() return M.db.sparkleOre end, Set("sparkleOre"))
    W:Check("Corpses you can skin", function() return M.db.sparkleCorpses end, Set("sparkleCorpses"),
        "A dead creature you can skin (or gather with Herbalism or Mining) is highlighted until you did it.\n|cffffd100Switches on the game's \"Enemy Unit Nameplates\"|r (Options > Nameplates) and, like all sparkles, \"Enable Interact Key\" (Options > Controls): only with both does the game give a corpse near you a nameplate the highlight can sit on. So every enemy shows a nameplate while this is on; put back as it was when it is off.")
    W:Check("Other world objects", function() return M.db.sparkleObjects end, Set("sparkleObjects"),
        "Also other things in the world you can interact with, each kind on or off below. With \"Colour by skill\": quest objects purple, the rest white.")
    local omark = H.Mark(wt)
    local tips = {
        quest = "Objects a quest in your log still wants (the game says so, or the tooltip shows progress like 3/8), and corpses with loot a quest still wants: yours or a group member's, until everyone has enough. Kill objectives don't count. Corpses only show with \"Corpses with loot\" or \"Corpses you can skin\" on (they switch on the game's enemy nameplates, which corpses need).",
        mailbox = "Mailboxes.",
        chest = "Chests, footlockers, strongboxes, lockboxes, coffers, trunks, caches, crates, barrels.",
        fishing = "Fishing schools and pools, floating wreckage and debris.",
        loot = "Dead creatures with loot left on them (corpses to skin are above).\n|cffffd100Switches on the game's \"Enemy Unit Nameplates\"|r (Options > Nameplates) and, like all sparkles, \"Enable Interact Key\" (Options > Controls): only with both does the game give a corpse near you a nameplate the highlight can sit on. So every enemy shows a nameplate while this is on; put back as it was when it is off.",
        other = "Everything else the interact key picks: doors, levers, chairs, books, ...",
    }
    for _, k in ipairs(mod.Sparkles.KINDS) do
        local key = k[1]
        W:Check("    " .. k[2], function() return M.db.sparkleKinds[key] ~= false end, function(v)
            M.db.sparkleKinds[key] = v and true or false
            mod.Sparkles.Update() MMT.Refresh()
        end, tips[key])
    end
    local objDep = H.After(omark)
    W:Space(6)
    W:Note("Only one thing at a time: what the interact key would pick, within 15 yards. Gathered nodes are learned, so new names sparkle from then on.")
    for _, w in ipairs(H.After(mark)) do dep[#dep + 1] = w end

    local lt2, Lk = Tile(panel, X2, 0, TILE_W, PANEL_H, "Look", "Interface\\Icons\\Spell_Holy_Aura")
    local lmark = H.Mark(lt2)
    Lk:Cycle("Look", {
        { value = "SPARKLES", text = "Sparkles" },
        { value = "BEAM", text = "Beam of light" },
    }, function() return M.db.sparkleStyle end, Set("sparkleStyle"))
    Lk:Check("Colour by skill", function() return M.db.sparkleColors end, Set("sparkleColors"),
        "Like recipes: orange, yellow, green (skill-ups likely to rare), grey (no skill-ups any more), red (skill too low). Quest objects are purple, other objects white. Off: the colour below.")
    Lk:Color("Colour", function() return M.db.sparkleColor end, Set("sparkleColor"))
    Lk:Slider("Size", 50, 200, 10, function() return M.db.sparkleSize end, Set("sparkleSize"), "%d%%")
    Lk:Slider("Height", -60, 60, 5, function() return M.db.sparkleHeight end, Set("sparkleHeight"))
    Lk:Check("Hide the game's interact icon", function() return M.db.sparkleHideIcon end, Set("sparkleHideIcon"),
        "The game's own icon over the object (switched on for the sparkles) is made see-through. Not with a game controller, which needs it.")
    for _, w in ipairs(H.After(lmark)) do dep[#dep + 1] = w end

    return function()
        local notHere = M.db.sparkles and not S.Allowed()
        leaderNote:SetText(notHere and NOT_HERE or "")
        H.Depend(dep, function() return M.db.sparkles end)
        H.Depend(objDep, function() return M.db.sparkles and M.db.sparkleObjects end)
    end
end

function M.Report(_, add)
    local method, partyIndex, raidIndex = mod.GetMethod()
    add(("-- Loot Distribution  current=%s partyML=%s raidML=%s threshold=%s isMaster=%s leader=%s"):format(
        tostring(method), tostring(partyIndex), tostring(raidIndex), tostring(mod.GetThreshold()),
        tostring(mod.IsMasterLooter()), tostring(IsInGroup() and UnitIsGroupLeader("player"))))
    add(("settings: auto=%s outsiderGroup=%s keepRaid=%s method=%s threshold=%s looter=%s byRoles=%s reserve=%s unassigned=%s rrNotice=%s multiRole=%s noRoom=%s autoPass=%s optOut=%s (game: %s) passExcept=%s optOutOutsider=%s"):format(
        tostring(M.db.autoMethod), tostring(M.db.outsiderGroup), tostring(M.db.keepRaid), tostring(M.db.method), tostring(M.db.threshold), tostring(M.db.looter),
        tostring(M.db.byRoles), tostring(M.db.reserve), tostring(M.db.unassigned), tostring(M.db.rrNotice),
        tostring(M.db.multiRole), tostring(M.db.noRoom), tostring(M.db.autoPass), tostring(M.db.optOut),
        tostring(GetOptOutOfLoot and GetOptOutOfLoot()), tostring(M.db.passExcept), tostring(M.db.optOutOutsider)))
    add("quest round robin=" .. tostring(M.db.questRR))
    if mod.QuestCacheReport then mod.QuestCacheReport(add) end
    if mod.StackCacheReport then mod.StackCacheReport(add) end
    if mod.DejunkReport then mod.DejunkReport(add) end
    local never = {}
    for _, e in ipairs(MMT.db.exclusions or {}) do if e.loot then never[#never + 1] = tostring(e.itemID) end end
    local others = {}
    for _, sk in ipairs(mod.skips) do others[#others + 1] = sk.name end
    add(("never loot: list=[%s] loot skips=[%s] worth=%s min=%s stack=%s"):format(table.concat(never, ","), table.concat(others, ","),
        tostring(M.db.worthOn), tostring(M.db.worthMin), tostring(M.db.worthStack)))
    if mod.Sparkles then mod.Sparkles.Report(add) end
    for _, c in ipairs(mod.choosers) do
        local on = true
        if c.active then local ok, v = pcall(c.active) on = ok and v and true or false end
        add(("  loot chooser %s (%s): %s"):format(c.name, tostring(c.title), on and "active" or "off"))
    end
    for itemID, key in pairs(M.store.questRR or {}) do add(("  quest item %s: last given to %s"):format(tostring(itemID), MMT.Repr(key))) end
    for _, key in ipairs(MMT.SortedMembers()) do
        local s = MMT.status[key]
        add(("  %s free=%s roles=[%s]"):format(MMT.Repr(key), tostring(s and s.free), table.concat(MMT.MemberRoleList(key), ",")))
    end
end
