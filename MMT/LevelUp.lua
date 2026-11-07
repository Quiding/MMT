-- MMT: "LvlUp available" in the Info window. Every client adds up the XP
-- rewards of its quests that are ready to turn in and sends the sum with the
-- heartbeat ("qx=<xp>", nothing without), and right away when it changes (at
-- most every 10 seconds). When a character's XP plus that sum reaches the next
-- level, its row shows a pulsing "LvlUp available" in place of the XP and rested
-- values, 5 seconds on, 5 seconds off (option "Highlight when I can level up").

local _, ns = ...

local function Plain(v) if v == nil or ns.IsSecret(v) then return nil end return v end

-- the XP reward of a quest in the log
local function RewardXP(questID, index)
    if not GetQuestLogRewardXP then return 0 end
    local ok, xp = pcall(GetQuestLogRewardXP, questID)
    xp = ok and tonumber(Plain(xp)) or 0
    if xp > 0 then return xp end
    -- classic API: the reward of the selected entry
    if index and not (C_QuestLog and C_QuestLog.GetInfo) and SelectQuestLogEntry and GetQuestLogSelection then
        local old = GetQuestLogSelection()
        SelectQuestLogEntry(index)
        ok, xp = pcall(GetQuestLogRewardXP)
        SelectQuestLogEntry(old or 0)
        xp = ok and tonumber(Plain(xp)) or 0
    end
    return xp
end

local function Ready(questID, complete)
    if C_QuestLog and C_QuestLog.ReadyForTurnIn then
        local ok, v = pcall(C_QuestLog.ReadyForTurnIn, questID)
        if ok and Plain(v) then return true end
    end
    if C_QuestLog and C_QuestLog.IsComplete then
        local ok, v = pcall(C_QuestLog.IsComplete, questID)
        if ok and Plain(v) then return true end
    end
    return complete == 1 or complete == true
end

-- { { id, title, xp }, ... } of the quests ready to turn in, and their XP together
local function ReadyQuests()
    local list, total = {}, 0
    local function Add(id, title, index, complete)
        id = tonumber(Plain(id))
        if not id or id <= 0 or not Ready(id, complete) then return end
        local xp = RewardXP(id, index)
        list[#list + 1] = { id = id, title = Plain(title), xp = xp }
        total = total + xp
    end
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, (tonumber(Plain(ns.Safe(C_QuestLog.GetNumQuestLogEntries))) or 0) do
            local info = ns.Safe(C_QuestLog.GetInfo, i)
            if type(info) == "table" and not info.isHeader then Add(info.questID, info.title, i, info.isComplete) end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, (GetNumQuestLogEntries() or 0) do
            local title, _, _, isHeader, _, complete, _, id = GetQuestLogTitle(i)
            if not isHeader then Add(id, title, i, complete) end
        end
    end
    return list, total
end

local own = 0   -- this character's turn-in XP (read on quest log changes)

-- XP of a member's quests that are ready to turn in
function ns.TurnInXP(key, s)
    if ns.IsSelf(key) then return own end
    s = s or ns.status[key]
    return s and s.ext and tonumber(s.ext.qx) or 0
end

-- turning in the ready quests would reach the next level
function ns.CanLevelUp(key, s)
    s = s or ns.status[key]
    if not s or s.isMax or (s.max or 0) <= 0 then return false end
    local xp = ns.TurnInXP(key, s)
    return xp > 0 and (s.cur or 0) + xp >= s.max
end

-- the 5 s on / 5 s off cycle: true while "LvlUp available" is shown
local function Phase() return math.floor(GetTime() / 5) % 2 == 0 end
function ns.LevelUpShowing(key, s)
    if ns.db.xp.levelUpHint == false or ns.db.xp.barMode == "REP" then return false end
    return Phase() and ns.CanLevelUp(key, s)
end

ns.CoreHeartbeat("qx", function() return own > 0 and tostring(own) or nil end)

-- the sum changed: tell the team (at most every 10 seconds)
local lastSent, lastAt, pending = nil, 0, false
local function SendIfChanged()
    pending = false
    if not ns.ready or own == lastSent then return end
    local wait = 10 - (GetTime() - lastAt)
    if wait > 0 then
        pending = true
        C_Timer.After(wait, SendIfChanged)
        return
    end
    lastSent, lastAt = own, GetTime()
    ns.BroadcastXP(true)
end

local function Read()
    local _, total = ReadyQuests()
    if total == own then return end
    own = total
    ns.Fire("STATUS_CHANGED")
    if not pending then SendIfChanged() end
end
local soon = false
local function ReadSoon()
    if soon then return end
    soon = true
    C_Timer.After(1, function() soon = false Read() end)
end
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "UNIT_QUEST_LOG_CHANGED" }) do
    ns.On(e, ReadSoon)
end
ns.OnLogin(function()
    C_Timer.After(3, Read)
    -- the 5 s cycle: redraw the window when it flips and somebody can level up
    local last = Phase()
    C_Timer.NewTicker(0.5, function()
        local now = Phase()
        if now == last then return end
        last = now
        if ns.db.xp.levelUpHint == false or not ns.UpdateXPWindow then return end
        for _, key in ipairs(ns.SortedMembers()) do
            if ns.CanLevelUp(key) then ns.UpdateXPWindow() return end
        end
        local me = ns.PlayerFull()
        if me and ns.CanLevelUp(me) then ns.UpdateXPWindow() end
    end)
end)

-- the row tooltip (XPWindow.lua)
function ns.LevelUpTooltip(tip, key, s)
    local xp = ns.TurnInXP(key, s)
    if xp <= 0 then return end
    local r, g, b = 0.75, 0.75, 0.75
    local text = ("%d XP"):format(xp)
    if ns.CanLevelUp(key, s) then r, g, b = 0.3, 1, 0.3 text = text .. " (level up)" end
    tip:AddDoubleLine("Ready quests", text, 1, 1, 1, r, g, b)
end

-- /mmt debug dump
function ns.LevelUpReport(add)
    local list, total = ReadyQuests()
    add(("-- Level up  turn-in XP=%d (sent %s)  can level=%s  hint=%s"):format(total, tostring(lastSent),
        tostring(ns.CanLevelUp(ns.PlayerFull() or "")), tostring(ns.db.xp.levelUpHint ~= false)))
    for _, q in ipairs(list) do add(("  ready %d %s xp=%d"):format(q.id, ns.Repr(q.title), q.xp)) end
end
