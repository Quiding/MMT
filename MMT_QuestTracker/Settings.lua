-- MMT Quest Tracker: settings page (under MODULES in /mmt) with sub-tabs (Tracker,
-- Order, Automation, Fonts) in the tile design, and the debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local A = UI.ACCENT
local H = MMT.ConfigHelpers
local COL_W, COL2_X, PAGE_W = H.COL_W, H.COL2_X, H.PAGE_W
local StatusLine, ConfirmButton = H.StatusLine, H.ConfirmButton

local function Opt(key)
    return function() return M.db[key] end,
           function(v) M.db[key] = v end
end

local function FontChoices(current)
    local l = {}
    for _, f in ipairs(MMT.fonts) do l[#l + 1] = { value = f.name, text = f.name } end
    local known = false
    for _, c in ipairs(l) do if c.value == current then known = true end end
    if current and not known then l[#l + 1] = { value = current, text = "Custom" } end
    return l
end

M.Page = function(_, page)
    local Tile, TILE_W, X2 = H.Tile, H.TILE_W, H.TILE_W + H.TILE_GAP
    local TILE_IN = TILE_W - 16
    local TOP = H.Intro(page, "One quest tracker for the whole team: every member's progress under each quest, plus quest automation and sharing.")
    local tabs, _, PANEL_H = H.TabStrip(page, TOP, {
        { "tracker", "Tracker", "INV_Misc_Book_09" },
        { "order", "Order", "INV_Misc_Map_01" },
        { "auto", "Automation", "INV_Misc_Gear_01" },
        { "fonts", "Fonts", "INV_Misc_Note_01" },
    }, H.SYNC_RESERVE)
    local status

    -------------------------------------------------------------------------
    -- Tracker: Quest Tracker + Content (left), Look (right)
    -------------------------------------------------------------------------
    local T = tabs.tracker
    local QT_H = 42 + 6 * UI.ROW + 10
    local _, L = Tile(T, 0, 0, TILE_W, QT_H, "Quest Tracker", "Interface\\Icons\\INV_Misc_Book_09")
    L:Check("Show quest tracker", Opt("show"))
    local ghb, shb = Opt("hideBlizzard")
    L:Check("Hide the Blizzard quest tracker", ghb, shb, "Comes back when you switch this off or disable the module (outside combat).")
    local gho, sho = Opt("hideOthers")
    L:Check("Hide other addons' quest trackers", gho, sho, "Hides the quest trackers of " .. mod.OtherTrackerNames() ..
        " (when they are loaded). Their own settings stay as they are; the trackers come back when you switch this off or disable the module (outside combat).")
    local glk, slk = Opt("locked")
    L:Check("Lock position", glk, slk, "Unlocked, Shift + drag moves the tracker.")
    local gct, sct = Opt("clickThrough")
    L:Check("Click-through", gct, sct, "Clicks go through the tracker to the game world. No collapsing, scrolling or tooltips then.")
    local gsh, ssh = Opt("showHeader")
    L:Check("Show header", gsh, ssh, "\"Quests 12/25\" at the top, with [-] / [+] on the right to collapse everything down to the zones or open everything.")

    local CY = -(QT_H + 8)
    local ct
    ct, L = Tile(T, 0, CY, TILE_W, PANEL_H + CY, "Content", "Interface\\Icons\\INV_Misc_Spyglass_02")
    local gw, sw = Opt("onlyWatched")
    L:Check("Only quests you track", gw, sw, "Only quests marked for tracking in your quest log.")
    local gtq, stq = Opt("teamQuests")
    L:Check("Include quests only teammates have", gtq, stq, "Quests your current character doesn't have, but someone in the team does.")
    local gm, sm = Opt("showMissing")
    L:Check("Show members not on the quest", gm, sm, "Adds \"not on quest\" for team members who don't have it. Members who already completed it always show \"completed\".")
    local go, so = Opt("showOffline")
    L:Check("Include offline members", go, so, "Shows their last known progress.")
    L:Check("Class colours for names", Opt("classColors"))
    local glc, slc = Opt("levelColors")
    L:Check("Quest level in difficulty colour", glc, slc, "Colours the [level] by how hard the quest is for your character.")
    L:Space(6)
    L:Button("Request update from team", function()
        mod.RequestAll()
        status.Show_("Asked the online team for their quest logs.")
    end)
    status = StatusLine(ct)
    status:SetWidth(TILE_IN)
    L:Add(status, 20)

    local _, R = Tile(T, X2, 0, TILE_W, PANEL_H, "Look", "Interface\\Icons\\INV_Misc_Ribbon_01")
    local gbg, sbg = Opt("bg")
    R:Color("Background colour", gbg, sbg)
    local gba, sba = Opt("bgAlpha")
    R:Slider("Background opacity", 0, 1, 0.05, gba, sba, "%.2f")
    local gwi, swi = Opt("width")
    R:Slider("Width", 150, 500, 5, gwi, swi)
    local gmh, smh = Opt("maxHeight")
    R:Slider("Maximum height (scrolls beyond)", 100, 1000, 10, gmh, smh)
    local gin, sin = Opt("indent")
    R:Slider("Indent per level", 0, 30, 1, gin, sin)
    local gsc, ssc = Opt("scale")
    R:Slider("Scale", 0.5, 2, 0.05, gsc, ssc, "%.2f")
    local gal, sal = Opt("align")
    local alignCycle = R:Cycle("Text alignment", {
        { value = "LEFT", text = "Left" },
        { value = "RIGHT", text = "Right" },
    }, function() return gal() == "RIGHT" and "RIGHT" or "LEFT" end, sal)
    UI.Tooltip(alignCycle, "Text alignment", "The whole tracker: Right lines up every row at the right edge, with the indents and the +/- coming from the right too.")
    local gol, sol = Opt("outline")
    R:Cycle("Outline", {
        { value = "NONE", text = "None" },
        { value = "OUTLINE", text = "Thin" },
        { value = "THICKOUTLINE", text = "Thick" },
        { value = "MONOCHROME,OUTLINE", text = "Mono" },
    }, gol, sol)
    local half = math.floor((TILE_IN - 8) / 2)
    local rt = R.parent
    local expand = UI.Button(rt, half, "Expand all", function() mod.SetAllCollapsed(false) end)
    R:Add(expand, 0)
    local resetPos = UI.Button(rt, half, "Reset position", function() mod.ResetPosition() end)
    resetPos:SetPoint("LEFT", expand, "RIGHT", 8, 0)
    R:Space(UI.ROW + 6)
    R:Note("In the tracker: Shift + drag moves it. Quest: click opens it in the quest log, Shift-click links it, Shift-right-click abandons it. Zone: Ctrl-click collapses its quests, Ctrl-right-click shows only that zone (again: all).")

    -------------------------------------------------------------------------
    -- Order: Zones (left), Quests (right) - Arrange.lua
    -------------------------------------------------------------------------
    local Or = tabs.order
    local _, ZL = Tile(Or, 0, 0, TILE_W, PANEL_H, "Zones", "Interface\\Icons\\INV_Misc_Map_01")
    local gcz, scz = Opt("currentZoneFirst")
    ZL:Check("Zone you are in first", gcz, scz, "The zone you are in goes to the top of the tracker (in a dungeon: its quests, when the quest log lists them under the dungeon's name).")
    local goz, soz = Opt("otherZones")
    local ozCycle = ZL:Cycle("Other zones", {
        { value = "show", text = "Show" },
        { value = "collapse", text = "Collapse" },
        { value = "hide", text = "Hide" },
    }, goz, soz)
    UI.Tooltip(ozCycle, "Other zones", "While the zone you are in has quests: the other zones stay as they are (Show), are collapsed to their name (Collapse; open one with its +, it stays open until you change zone), or are left out (Hide). In a zone without quests, all zones show. A zone focus (Ctrl-right-click) goes first.")
    local gzo, szo = Opt("zoneOrder")
    local zoCycle = ZL:Cycle("Order of the zones", {
        { value = "log", text = "Quest log" },
        { value = "near", text = "Nearest first" },
        { value = "name", text = "A - Z" },
    }, gzo, szo)
    UI.Tooltip(zoCycle, "Order of the zones", "Nearest first: zones on your continent by distance (to the nearest quest objective with Questie, otherwise to the middle of the zone), then other continents, then headers that aren't zones (class quests and the like). Re-sorted while you move.")
    ZL:Space(4)
    ZL:Note("Quests only teammates have are sorted into their zones too.")

    local _, QR = Tile(Or, X2, 0, TILE_W, PANEL_H, "Quests", "Interface\\Icons\\INV_Misc_Note_02")
    local gqo, sqo = Opt("questOrder")
    local qoCycle = QR:Cycle("Order in a zone", {
        { value = "log", text = "Quest log" },
        { value = "level", text = "Level" },
        { value = "progress", text = "Team progress" },
        { value = "near", text = "Nearest first" },
    }, gqo, sqo)
    UI.Tooltip(qoCycle, "Order in a zone", "Quest log: as in your quest log (teammates' quests after yours). Level: lowest first. Team progress: the quests the team is furthest along with first. Nearest first: by distance to the nearest open objective (or the quest giver once done); needs Questie, without it the quest log order stays.")
    local grq, srq = Opt("readyQuests")
    local rqCycle = QR:Cycle("Quests ready to turn in", {
        { value = "keep", text = "In order" },
        { value = "top", text = "On top" },
        { value = "bottom", text = "At the bottom" },
    }, grq, srq)
    UI.Tooltip(rqCycle, "Quests ready to turn in", "Quests every shown character is done with.")
    local guq, suq = Opt("useQuestie")
    QR:Check("Distances from Questie", guq, suq, "When Questie is loaded, \"Nearest first\" uses its database: the nearest spot of each open objective of the quests in your log. Questie's own tracker stays hidden (Tracker tab).")
    QR:Space(4)
    QR:Note(mod.QuestieAvailable() and "Questie is loaded." or "Questie is not loaded: zones go by their middle, quests keep the quest log order.")

    -------------------------------------------------------------------------
    -- Automation: Quests (left), Team (right)
    -------------------------------------------------------------------------
    local Au = tabs.auto
    local _, L2 = Tile(Au, 0, 0, TILE_W, PANEL_H, "Quests", "Interface\\Icons\\INV_Misc_Note_02")
    L2:Check("Accept quests from NPCs", Opt("acceptNPC"))
    L2:Check("Accept quests shared by group", Opt("acceptShared"))
    L2:Check("Turn in completed quests", Opt("turnIn"))
    local gt, st = Opt("skipTrivial")
    L2:Check("Skip grey (low level) quests", gt, st, "Grey quests are not picked up from NPC dialogs.")
    local gan, san = Opt("announce")
    L2:Check("Announce quest completion in party chat", gan, san,
        "Posts \"[Quest] is ready for turn-in.\" in party chat when one of your quests becomes ready to turn in.")
    local gst, sst = Opt("announceStarter")
    L2:Check("Announce looted items that start a quest", gst, sst,
        "Posts \"Looted [Item] - it starts a quest!\" in party chat when an item that starts a quest lands in your bags (not if that quest is already in your log). Not in a group: only shown to you.")
    local gmr, smr = Opt("markRewards")
    L2:Check("Mark the best rewards", gmr, smr,
        "On quest reward choices: a coin on the reward that sells for the most, a green arrow on every reward that is an upgrade for this character (it can wear it and its item level is higher than what it wears in that slot). Choosing stays manual.")
    L2:Space(4)
    L2:Note("Hold Shift while an NPC page opens to keep that page manual (Core > Automations).")

    local _, R2 = Tile(Au, X2, 0, TILE_W, PANEL_H, "Team", "Interface\\Icons\\Spell_Holy_PrayerOfFortitude")
    local gas, sas = Opt("autoShare")
    R2:Check("Share new quests automatically", gas, sas,
        "When you accept a quest, it is shared with your group. Quests you got shared by a group member, or that every team member already has, aren't shared again.")
    local gns, sns = Opt("announceNoShare")
    R2:Check("Announce if a quest can't be shared", gns, sns,
        "Posts \"[Quest] can't be shared.\" in party chat when you accept a quest that the game doesn't let you share.")
    local gab, sab = Opt("abortTeam")
    R2:Check("Abandon quests on the whole team", gab, sab,
        "When you abandon a quest, you are asked: \"Do you want to abort this quest on your entire team?\". Yes makes every online team member abandon it too. Must be on for the other characters as well.")
    R2:Space(4)
    R2:Note("Sharing and team abandon need MMT with this module on every client.")

    -------------------------------------------------------------------------
    -- Fonts: one tile per level (font, size, colour), two by two
    -------------------------------------------------------------------------
    local Fo = tabs.fonts
    local FONT_H = 42 + (UI.ROW + 2) + 36 + (UI.ROW + 2) + 10
    for i, level in ipairs(mod.LEVELS) do
        local x = ((i - 1) % 2 == 0) and 0 or X2
        local y = -math.floor((i - 1) / 2) * (FONT_H + 8)
        local _, C = Tile(Fo, x, y, TILE_W, FONT_H, level.title, "Interface\\Icons\\INV_Misc_Note_01")
        local function S() return M.db.fonts[level.key] end
        C:Cycle("Font", function() return FontChoices(S().font) end,
            function() return S().font end, function(v) S().font = v end)
        C:Slider("Font size", 6, 24, 1, function() return S().size end, function(v) S().size = v end)
        C:Color("Font colour", function() return S().color end, function(v) S().color = v end)
    end
    local note = UI.Label(Fo, "Zone > [Level] Quest > Objective > one row per team member (ready everywhere: only the quest; only you: progress behind the objective). +/- collapses / expands a line.")
    note:SetTextColor(0.6, 0.6, 0.6)
    note:SetWidth(PAGE_W)
    note:SetJustifyH("LEFT")
    note:SetPoint("TOPLEFT", 0, -(math.ceil(#mod.LEVELS / 2) * (FONT_H + 8)) - 2)
end

function M.Report(_, add)
    add(("-- Quest Tracker  own hash=%s  own quests=%d  blizzard tracker parent=%s"):format(
        tostring(mod.OwnHash()), #(mod.ownOrder or {}),
        tostring(_G.ObjectiveTrackerFrame and _G.ObjectiveTrackerFrame:GetParent() and
            (_G.ObjectiveTrackerFrame:GetParent():GetName() or "hidden") or "n/a")))
    add(("automation: acceptNPC=%s acceptShared=%s turnIn=%s skipTrivial=%s announce=%s autoShare=%s announceNoShare=%s abortTeam=%s announceStarter=%s"):format(
        tostring(M.db.acceptNPC), tostring(M.db.acceptShared), tostring(M.db.turnIn), tostring(M.db.skipTrivial),
        tostring(M.db.announce), tostring(M.db.autoShare), tostring(M.db.announceNoShare), tostring(M.db.abortTeam), tostring(M.db.announceStarter)))
    local watchedN = 0
    for _ in pairs(mod.ownWatched or {}) do watchedN = watchedN + 1 end
    add(("tracker: onlyWatched=%s teamQuests=%s showMissing=%s focusZone=%s tracked=%d"):format(
        tostring(M.db.onlyWatched), tostring(M.db.teamQuests), tostring(M.db.showMissing),
        MMT.Repr(M.store.focusZone), watchedN))
    add(("other trackers: hideOthers=%s  %s"):format(tostring(M.db.hideOthers), mod.OtherTrackersReport()))
    add(mod.ArrangeReport())
    if mod.QuestXPReport then add(mod.QuestXPReport()) end
    for _, id in ipairs(mod.ownOrder or {}) do
        local own = mod.AllData()[MMT.PlayerFull()]
        local q = own and own.quests and own.quests[id]
        add(("  own quest %s %s zone=%s tracked=%s"):format(tostring(id), MMT.Repr(q and q.title),
            MMT.Repr(q and q.zone), tostring(mod.ownWatched and mod.ownWatched[id] or false)))
        -- what the game says right now next to what the tracker holds
        local game = {}
        local ok, list = pcall(function() return C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id) end)
        for i, o in ipairs(ok and list or {}) do
            local held = q and q.obj and q.obj[i]
            game[#game + 1] = ("%s/%s %s %s [held %s/%s%s]"):format(tostring(o.numFulfilled), tostring(o.numRequired), MMT.Repr(o.text),
                tostring(o.type), tostring(held and held.have), tostring(held and held.need), held and held.counted and " MMT count" or "")
        end
        if #game > 0 then add("    objectives: " .. table.concat(game, "; ")) end
    end
    for key, rec in pairs(mod.AllData()) do
        add(("quests %s: %d, hash %s, %s"):format(MMT.Repr(key), mod.QuestCount(rec), tostring(rec.hash), MMT.Ago(rec.time)))
    end
    for key, set in pairs(M.store.questsDone or {}) do
        local ids = {}
        for id in pairs(set) do ids[#ids + 1] = id end
        table.sort(ids)
        add(("completed (of the team's open quests) %s: %s"):format(MMT.Repr(key), #ids > 0 and table.concat(ids, ",") or "none"))
    end
end
