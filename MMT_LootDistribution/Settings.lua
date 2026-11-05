-- MMT Loot Distribution: settings page (under MODULES in /mmt) and debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X, PAGE_W = H.COL_W, H.COL2_X, H.PAGE_W
local StatusLine = H.StatusLine

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
    }, H.SYNC_RESERVE)
    local SparklesTab = mod.SparklesTab
    page = panels.loot
    local TOP = 0
    local TOP_H, BOTTOM_H = 320, 124
    local Y2 = TOP - TOP_H - 8

    -- Loot Method (top left) ----------------------------------------------------------------
    local lt, L = Tile(page, 0, TOP, TILE_W, TOP_H, "Loot Method", "Interface\\Icons\\INV_Misc_Bag_10")
    local gog, sog = Opt("outsiderGroup")
    L:Check("Return to Group Loot when outsiders join", gog, sog,
        "While a player who isn't in your team list is in the group, the loot method is Group Loot with the threshold Uncommon. When they leave, the method and threshold below are set again.")
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
    }, gmr, smr)
    UI.Tooltip(masterOnly[#masterOnly], "Several have the role",
        "Fill up by team order: the first of them in team order gets everything until their bags are full (keeping the free slots below), then the next. Round robin: they get the items in turns.")
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
    local gu, su = Opt("unassigned")
    masterOnly[#masterOnly + 1] = R:Cycle("No role wants it", {
        { value = "LEAVE", text = "Leave for manual" },
        { value = "SELF", text = "Give to master looter" },
        { value = "RR", text = "Round robin to the team" },
    }, gu, su)
    local grr, srr = Opt("rrNotice")
    masterOnly[#masterOnly + 1] = R:Check("Say so in chat (round robin)", grr, srr,
        "Prints \"[Item] is not part of any role or rule, so it was given round robin to <Name>.\" (only for you). Round robin keeps the free bag slots above; quest items are never part of it.")
    local grep, srep = Opt("report")
    masterOnly[#masterOnly + 1] = R:Check("Report in chat", grep, srep, "Prints each item given and the loot settings that were applied (only for you).")
    masterOnly[#masterOnly + 1] = R:Note("Bind on Pickup items are never given out or looted: they are posted in group chat, and the master looter assigns them by hand. Items without loaded item data are left alone, too.")
    local hint = R:Note("")

    R:Header("Quest items")
    local gq, sq = Opt("questRR")
    masterOnly[#masterOnly + 1] = R:Check("Auto-Round Robin quest items", gq, sq,
        "As master looter, quest items go to the team members in turns, in team order. Only characters the game offers for the item (on the quest and able to receive it) get a turn. Turns are kept per item, so drops spread evenly. The free bag slots setting doesn't apply: quest items are given even into the last slot.")

    local sparklesRefresh = SparklesTab(panels.sparkles, PANEL_H)
    page = root
    page.OnRefresh = function()
        sparklesRefresh()
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

-- Sparkles tab: what sparkles (left), how it looks (right)
function mod.SparklesTab(panel, PANEL_H)
    local Tile, TILE_W, X2 = H.Tile, H.TILE_W, H.TILE_W + H.TILE_GAP
    local S = mod.Sparkles
    local function Set(key) return function(v) M.db[key] = v S.Update() MMT.Refresh() end end
    local dep = {}

    local wt, W = Tile(panel, 0, 0, TILE_W, PANEL_H, "Highlight in the World", "Interface\\Icons\\INV_Misc_Herb_10")
    W:Check("Sparkles", function() return M.db.sparkles end, Set("sparkles"),
        "Highlights the herb, ore vein, corpse or object right in front of you, as long as you have the skill to gather it.\nThe game only tells addons about the one thing the interact key would pick (close by, in front of you), so only that one is highlighted, not everything around you.\nSwitches on (out of combat) the game's interact key target, its nameplate and icon, and a reach of 15 yards all around you; put back as it was when this is off.")
    local mark = H.Mark(wt)
    W:Space(4)
    W:Check("Herbs (Herbalism)", function() return M.db.sparkleHerbs end, Set("sparkleHerbs"))
    W:Check("Ore veins (Mining)", function() return M.db.sparkleOre end, Set("sparkleOre"))
    W:Check("Corpses you can skin", function() return M.db.sparkleCorpses end, Set("sparkleCorpses"),
        "A dead creature you can skin (or gather with Herbalism or Mining) is highlighted until you did it.")
    W:Check("Other world objects", function() return M.db.sparkleObjects end, Set("sparkleObjects"),
        "Also other things in the world you can interact with, each kind on or off below. With \"Colour by skill\": quest objects blue, the rest white.")
    local omark = H.Mark(wt)
    local tips = {
        quest = "Objects a quest in your log still wants (the game says so, or the tooltip shows progress like 3/8).",
        mailbox = "Mailboxes.",
        chest = "Chests, footlockers, strongboxes, lockboxes, coffers, trunks, caches, crates, barrels.",
        fishing = "Fishing schools and pools, floating wreckage and debris.",
        loot = "Dead creatures with loot left on them (corpses to skin are above).",
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
        "Like recipes: orange, yellow, green (skill-ups likely to rare), grey (no skill-ups any more), red (skill too low). Other objects are white. Off: the colour below.")
    Lk:Color("Colour", function() return M.db.sparkleColor end, Set("sparkleColor"))
    Lk:Slider("Size", 50, 200, 10, function() return M.db.sparkleSize end, Set("sparkleSize"), "%d%%")
    Lk:Slider("Height", -60, 60, 5, function() return M.db.sparkleHeight end, Set("sparkleHeight"))
    Lk:Check("Hide the game's interact icon", function() return M.db.sparkleHideIcon end, Set("sparkleHideIcon"),
        "The game's own icon over the object (switched on for the sparkles) is made see-through. Not with a game controller, which needs it.")
    for _, w in ipairs(H.After(lmark)) do dep[#dep + 1] = w end

    return function()
        H.Depend(dep, function() return M.db.sparkles end)
        H.Depend(objDep, function() return M.db.sparkles and M.db.sparkleObjects end)
    end
end

function M.Report(_, add)
    local method, partyIndex, raidIndex = mod.GetMethod()
    add(("-- Loot Distribution  current=%s partyML=%s raidML=%s threshold=%s isMaster=%s leader=%s"):format(
        tostring(method), tostring(partyIndex), tostring(raidIndex), tostring(mod.GetThreshold()),
        tostring(mod.IsMasterLooter()), tostring(IsInGroup() and UnitIsGroupLeader("player"))))
    add(("settings: auto=%s outsiderGroup=%s method=%s threshold=%s looter=%s byRoles=%s reserve=%s unassigned=%s rrNotice=%s multiRole=%s noRoom=%s autoPass=%s optOut=%s (game: %s) passExcept=%s"):format(
        tostring(M.db.autoMethod), tostring(M.db.outsiderGroup), tostring(M.db.method), tostring(M.db.threshold), tostring(M.db.looter),
        tostring(M.db.byRoles), tostring(M.db.reserve), tostring(M.db.unassigned), tostring(M.db.rrNotice),
        tostring(M.db.multiRole), tostring(M.db.noRoom), tostring(M.db.autoPass), tostring(M.db.optOut),
        tostring(GetOptOutOfLoot and GetOptOutOfLoot()), tostring(M.db.passExcept)))
    add("quest round robin=" .. tostring(M.db.questRR))
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
