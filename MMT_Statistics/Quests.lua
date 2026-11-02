-- MMT Statistics: quests of this account's characters.
--
-- Per character: c.quests[questID] = {
--   n  = name, l = quest level,
--   st = "A" accepted | "C" completed | "X" abandoned,
--   cl = character level at completion, xp = experience, cp = money (copper),
--   items = item rewards (fixed ones and the chosen one, see below),
--   ta = accepted at, tc = completed at, tx = abandoned at (time()),
--   scan = true   -- found by "Scan completed quests": no date, xp or money
-- }
-- Events: QUEST_ACCEPTED, QUEST_TURNED_IN (with the xp and money reward) and
-- QUEST_REMOVED (turned in or abandoned: abandoned when no QUEST_TURNED_IN
-- came for it and the game doesn't flag it as completed).
-- Names and levels come from the quest log; for scanned quests from
-- Questie's database (QuestieDB) when it is loaded, else from the game's
-- quest cache (loaded on request, filled in as it arrives).

local _, mod = ...
local MMT = MMT
local M = mod.M

local Safe, IsSecret = MMT.Safe, MMT.IsSecret
local function Plain(v) if v == nil or IsSecret(v) then return nil end return v end

mod.QUEST_STATUS = { A = "accepted", C = "completed", X = "abandoned" }

local function Quests(c)
    c = c or mod.Char()
    if not c then return nil end
    c.quests = c.quests or {}
    return c.quests
end
mod.Quests = Quests

-- name and level from the quest log (nil when not in it)
local function FromLog(questID)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetInfo then
        local index = Safe(C_QuestLog.GetLogIndexForQuestID, questID)
        local info = index and Safe(C_QuestLog.GetInfo, index)
        if type(info) == "table" and not info.isHeader then
            return Plain(info.title), Plain(info.level)
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, (GetNumQuestLogEntries() or 0) do
            local title, level, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            if not isHeader and id == questID then return Plain(title), Plain(level) end
        end
    end
end

-- name and level without the quest log: Questie's database, then the game
local function FromDatabase(questID)
    local db = _G.QuestDB   -- QuestieDB (LibQuestieDB.Quest)
    if type(db) == "table" and type(db.Get) == "function" then
        local okN, name = pcall(db.Get, questID, "name")
        local okL, level = pcall(db.Get, questID, "questLevel")
        if okN and type(name) == "string" and name ~= "" then
            return name, okL and tonumber(level) or nil
        end
    end
    local name = C_QuestLog and C_QuestLog.GetTitleForQuestID and Plain(Safe(C_QuestLog.GetTitleForQuestID, questID))
    if type(name) == "string" and name ~= "" then return name, nil end
end

local function Fill(questID, q)
    if q.n and q.l then return end
    local n, l = FromLog(questID)
    if not n then n, l = FromDatabase(questID) end
    q.n = q.n or n
    q.l = q.l or (tonumber(l) and tonumber(l) > 0 and tonumber(l) or nil)
end

---------------------------------------------------------------------------
-- Names the game has to load first (scanned quests)
---------------------------------------------------------------------------
local loadQueue, loading = {}, false
local function LoadNext()
    if #loadQueue == 0 then loading = false return end
    loading = true
    for _ = 1, 20 do
        local id = table.remove(loadQueue)
        if not id then break end
        if C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, id) end
    end
    C_Timer.After(0.5, LoadNext)
end
local function RequestName(questID)
    if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return end
    loadQueue[#loadQueue + 1] = questID
    if not loading then LoadNext() end
end
M:On("QUEST_DATA_LOAD_RESULT", function(questID, success)
    if not success or type(questID) ~= "number" then return end
    local q = Quests() and Quests()[questID]
    if q and not q.n then Fill(questID, q) end
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local turnedIn = {}   -- [questID] = GetTime(): QUEST_REMOVED right after = not abandoned

M:On("QUEST_ACCEPTED", function(a, b)
    if not M.db.trackQuests then return end
    -- Mainline: (questID); Classic: (questLogIndex, questID)
    local questID = (type(b) == "number" and b > 0) and b or a
    if type(questID) ~= "number" then return end
    local list = Quests()
    if not list then return end
    local q = list[questID] or {}
    list[questID] = q
    -- accepted again after abandoning (or a repeatable quest): a new start
    q.st, q.ta, q.tx = "A", time(), nil
    q.scan = nil
    C_Timer.After(0.5, function() Fill(questID, q) end)
    M:Debug("quest accepted %d", questID)
    if mod.Redraw then mod.Redraw() end
end)

---------------------------------------------------------------------------
-- Item rewards: read from the reward window (QUEST_COMPLETE); the choice is
-- the index passed to GetQuestReward (by the player's click or MMT's turn-in)
--   q.items = { { id = itemID, n = name, c = count, q = quality, pick = true|nil }, ... }
---------------------------------------------------------------------------
local offer   -- { questID, fixed = {...}, choices = {...}, pick = index }

local function ReadItems(kind, n)
    local list = {}
    for i = 1, n do
        local name, _, count, quality, _, itemID = GetQuestItemInfo(kind, i)
        local link = GetQuestItemLink and GetQuestItemLink(kind, i)
        itemID = Plain(itemID) or (link and tonumber(link:match("item:(%d+)")))
        name = Plain(name)
        if name or itemID then
            list[#list + 1] = { id = itemID, n = name, c = math.max(1, tonumber(Plain(count)) or 1), q = Plain(quality) }
        end
    end
    return list
end

M:On("QUEST_COMPLETE", function()
    if not M.db.trackQuests or not GetQuestItemInfo then return end
    local questID = GetQuestID and Plain(GetQuestID())
    if type(questID) ~= "number" or questID == 0 then offer = nil return end
    offer = {
        questID = questID,
        fixed = ReadItems("reward", GetNumQuestRewards and GetNumQuestRewards() or 0),
        choices = ReadItems("choice", GetNumQuestChoices and GetNumQuestChoices() or 0),
    }
end)
if hooksecurefunc and GetQuestReward then
    hooksecurefunc("GetQuestReward", function(choice)
        if offer then offer.pick = tonumber(choice) end
    end)
end

local function RewardItems(questID)
    if not offer or offer.questID ~= questID then return nil end
    local items = {}
    for _, it in ipairs(offer.fixed) do items[#items + 1] = it end
    local chosen = offer.pick and offer.choices[offer.pick]
    -- a single choice is handed out without picking
    if not chosen and #offer.choices == 1 then chosen = offer.choices[1] end
    if chosen then
        local c = {} for k, v in pairs(chosen) do c[k] = v end
        c.pick = true
        items[#items + 1] = c
    end
    offer = nil
    return #items > 0 and items or nil
end

-- "Linen Bag x1; Rough Arrow x200" (export, tooltips)
function mod.QuestItemsText(items, withIds)
    local out = {}
    for _, it in ipairs(items or {}) do
        local name = it.n or ("item " .. tostring(it.id))
        if withIds and it.id then name = ("%s (%d)"):format(name, it.id) end
        out[#out + 1] = ("%s x%d"):format(name, it.c or 1)
    end
    return table.concat(out, "; ")
end

M:On("QUEST_TURNED_IN", function(questID, xp, money)
    questID = Plain(questID)
    if not M.db.trackQuests or type(questID) ~= "number" then return end
    turnedIn[questID] = GetTime()
    local list = Quests()
    if not list then return end
    local q = list[questID] or {}
    list[questID] = q
    Fill(questID, q)
    q.st, q.tc, q.scan = "C", time(), nil
    q.cl = Plain(Safe(UnitLevel, "player"))
    q.xp = tonumber(Plain(xp)) or 0
    q.cp = tonumber(Plain(money)) or 0
    q.items = RewardItems(questID)
    M:Debug("quest completed %d xp=%s copper=%s", questID, tostring(q.xp), tostring(q.cp))
    if mod.Redraw then mod.Redraw() end
end)

M:On("QUEST_REMOVED", function(questID)
    questID = Plain(questID)
    if not M.db.trackQuests or type(questID) ~= "number" then return end
    -- QUEST_TURNED_IN comes first when it was turned in
    C_Timer.After(1, function()
        if turnedIn[questID] and GetTime() - turnedIn[questID] < 5 then turnedIn[questID] = nil return end
        local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
            and Safe(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if done then return end
        local list = Quests()
        local q = list and list[questID]
        if not q then
            q = {}
            list[questID] = q
        end
        if q.st == "C" then return end
        Fill(questID, q)
        q.st, q.tx = "X", time()
        M:Debug("quest abandoned %d", questID)
        if mod.Redraw then mod.Redraw() end
    end)
end)

---------------------------------------------------------------------------
-- Scan: completed quests (and the quest log) of this character
---------------------------------------------------------------------------
-- Quests MMT already has keep their data; one MMT still has as accepted or
-- abandoned but the game says is completed becomes completed (without
-- xp/money). Returns new completed, updated, new in the log, names missing.
function mod.ScanQuests()
    local list = Quests()
    if not list then return 0, 0, 0, 0 end
    local ids = {}
    if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        local ok, all = pcall(C_QuestLog.GetAllCompletedQuestIDs)
        if ok and type(all) == "table" then for _, id in ipairs(all) do ids[#ids + 1] = id end end
    elseif GetQuestsCompleted then
        local ok, all = pcall(GetQuestsCompleted)
        if ok and type(all) == "table" then for id in pairs(all) do ids[#ids + 1] = id end end
    end
    local added, updated, inLog, unnamed = 0, 0, 0, 0
    for _, id in ipairs(ids) do
        local q = list[id]
        if not q then
            q = { st = "C", scan = true }
            list[id] = q
            added = added + 1
        elseif q.st ~= "C" then
            q.st = "C"
            updated = updated + 1
        end
        Fill(id, q)
        if not q.n then unnamed = unnamed + 1; RequestName(id) end
    end
    -- quests in the log right now: accepted (date unknown)
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, (Safe(C_QuestLog.GetNumQuestLogEntries) or 0) do
            local info = Safe(C_QuestLog.GetInfo, i)
            local id = type(info) == "table" and not info.isHeader and Plain(info.questID)
            if type(id) == "number" and id > 0 and not list[id] then
                list[id] = { st = "A", scan = true, n = Plain(info.title), l = Plain(info.level) }
                inLog = inLog + 1
            end
        end
    end
    return added, updated, inLog, unnamed
end

function mod.QuestCounts(c)
    local n = { A = 0, C = 0, X = 0 }
    for _, q in pairs(c and c.quests or {}) do if n[q.st] then n[q.st] = n[q.st] + 1 end end
    return n
end

M.QuestReport = function(add)
    local c = mod.Char()
    local n = mod.QuestCounts(c)
    add(("  quests (this character): accepted=%d completed=%d abandoned=%d questieDB=%s"):format(
        n.A, n.C, n.X, tostring(type(_G.QuestDB) == "table")))
end
