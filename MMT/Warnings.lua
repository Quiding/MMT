-- MMT: warnings for full bags and a full quest log (Alerts page; as in
-- MBAssist).
--
-- Every client watches its own character and tells the leader (FTL leader,
-- or the group leader without one) when it gets low on room:
--   NOTE:WARN:BAGS:<free slots>
--   NOTE:WARN:QLOG:<quests>:<maximum>
-- Each warns once when it crosses the limit, and once more when it is
-- completely full; it warns again only after there was room again.
-- On the leader's client: a chat line, optionally a raid warning and sound;
-- warnings arriving within 2 seconds share one line.

local _, ns = ...

local function Cfg() return ns.db and ns.db.warn end

---------------------------------------------------------------------------
-- Leader: show the warning
---------------------------------------------------------------------------
local RAID_WARNING_SOUND = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959

-- warnings arriving within 2 seconds become one line (and one raid warning / sound):
--   Bags: John full, Monika 2 free.  Quest log: Apple full (25/25).
local function Show(list)
    local cfg = Cfg()
    local bags, quests = {}, {}
    for _, w in ipairs(list) do
        if w.kind == "BAGS" then
            bags[#bags + 1] = w.who .. " " .. (w.a == 0 and "full" or (w.a .. " free"))
        else
            quests[#quests + 1] = ("%s %s (%d/%d)"):format(w.who, w.a >= w.b and "full" or "almost full", w.a, w.b)
        end
    end
    local lines = {}
    if #bags > 0 then lines[#lines + 1] = "Bags: " .. ns.AndList(bags) .. "." end
    if #quests > 0 then lines[#lines + 1] = "Quest log: " .. ns.AndList(quests) .. "." end
    if #lines == 0 then return end
    local text = table.concat(lines, "  ")
    ns.Print("|cffffa020%s|r", text)
    if cfg.raidWarning and RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = 1, g = 0.63, b = 0.13 })
    end
    if cfg.sound then pcall(PlaySound, RAID_WARNING_SOUND, "Master") end
end
local warnings = ns.ChatBatch(2, Show)

local function Add(key, kind, a, b)
    -- the same warning about the same character at most once every few seconds
    if not ns.AlertAllowed("warn", ("%s:%s:%s:%s"):format(key, kind, a, tostring(b))) then return end
    warnings.Add({ who = ns.ShownName(key), kind = kind, a = a, b = b or 0 })
end

ns.Listen("TEAM_MESSAGE", function(key, sender, text, _, channel)
    local kind, a, b = text:match("^NOTE:WARN:(%u+):(%d+):?(%d*)$")
    if not kind or not ns.AcceptNotice(channel) then return end
    Add(key, kind, tonumber(a), tonumber(b))
end)

local function Report(kind, a, b)
    local msg = ("NOTE:WARN:%s:%d%s"):format(kind, a, b and (":" .. b) or "")
    local result = ns.TellLeader and ns.TellLeader(msg)
    if result == "self" then Add(ns.PlayerFull(), kind, a, b) end
end

---------------------------------------------------------------------------
-- Own character
---------------------------------------------------------------------------
-- level: 0 room, 1 low, 2 full; a warning when the level goes up
local bagLevel, questLevel

local function QuestCounts()
    local quests
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local _, n = C_QuestLog.GetNumQuestLogEntries()
        quests = n
    elseif GetNumQuestLogEntries then
        local _, n = GetNumQuestLogEntries()
        quests = n
    end
    local max = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept())
        or MAX_QUESTS or 25
    return quests, max
end

local function Check()
    local cfg = Cfg()
    if not (cfg and ns.ready) then return end

    if cfg.bags then
        local s = ns.UpdateOwnStatus()
        local free = s and s.free
        if free then
            local level = free == 0 and 2 or (free <= (cfg.bagsAt or 2) and 1 or 0)
            if bagLevel ~= nil and level > bagLevel then Report("BAGS", free) end
            bagLevel = level
        end
    end

    if cfg.quests then
        local n, max = QuestCounts()
        if n and max and max > 0 then
            local left = max - n
            local level = left <= 0 and 2 or (left <= (cfg.questsAt or 3) and 1 or 0)
            if questLevel ~= nil and level > questLevel then Report("QLOG", n, max) end
            questLevel = level
        end
    end
end
ns.CheckRoomWarnings = Check

local pending = false
local function CheckSoon()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function() pending = false Check() end)
end

ns.On("BAG_UPDATE_DELAYED", CheckSoon)
ns.On("QUEST_ACCEPTED", CheckSoon)
ns.On("QUEST_REMOVED", CheckSoon)
ns.On("QUEST_LOG_UPDATE", CheckSoon)
-- the state at login is only remembered: no warning for what was full before
ns.OnLogin(function() C_Timer.After(3, Check) end)
