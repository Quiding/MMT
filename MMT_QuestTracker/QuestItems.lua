-- MMT_QuestTracker: quest item buttons - the item a quest of your own wants you
-- to use (the game's "special" quest log item), as a clickable button beside the
-- quest's row, like the Blizzard tracker. Option "Quest item buttons" (on).
--
-- The buttons are secure (SecureActionButtonTemplate, type "item"): the game lets
-- them be created, moved, shown and hidden only outside combat. So they are
-- parented to UIParent and placed by screen position (anchoring them to the
-- tracker rows would lock the tracker in combat too). In combat they stay where
-- they are; after combat (and after every redraw outside combat) they move to
-- their rows again. Cooldown and charges update any time.

local _, mod = ...
local M = mod.M

local pool = {}       -- buttons, reused
local placed = 0      -- how many are in use
local pending = false -- a placement waits for the end of combat
local stats = { placed = 0, waited = 0, last = nil }

local function Enabled()
    return M.enabled and M.db.show and M.db.questItems ~= false
end

-- the quest's special item: link, icon, charges, logIndex (or nil)
local function QuestItem(questID)
    if not (questID and C_QuestLog and C_QuestLog.GetLogIndexForQuestID and GetQuestLogSpecialItemInfo) then return nil end
    local index = C_QuestLog.GetLogIndexForQuestID(questID)
    if not index then return nil end
    local ok, link, icon, charges, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, index)
    if not ok or not link or MMT.IsSecret(link) then return nil end
    if not showWhenComplete and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then return nil end
    return link, icon, charges, index
end
mod.QuestItem = QuestItem

local function Button(i)
    local b = pool[i]
    if b then return b end
    b = CreateFrame("Button", "MMTQuestItemButton" .. i, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    b:SetFrameStrata("MEDIUM")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:SetColorTexture(0, 0, 0, 0.8)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 1, 0)
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        if not self.logIndex then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if not pcall(GameTooltip.SetQuestLogSpecialItem, GameTooltip, self.logIndex) then
            GameTooltip:SetHyperlink(self.link)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:Hide()
    pool[i] = b
    return b
end

local function UpdateCooldown(b)
    if not (b.logIndex and GetQuestLogSpecialItemCooldown) then return end
    local ok, start, duration, enable = pcall(GetQuestLogSpecialItemCooldown, b.logIndex)
    if ok and start and duration and duration > 0 and enable ~= 0 then
        b.cooldown:SetCooldown(start, duration)
    else
        b.cooldown:Clear()
    end
end

-- cooldowns and charges (no position change: fine in combat)
function mod.UpdateQuestItems()
    for i = 1, placed do
        local b = pool[i]
        if b and b.questID then
            local link, icon, charges, index = QuestItem(b.questID)
            if link then
                b.logIndex = index
                b.icon:SetTexture(icon)
                b.count:SetText((charges and charges > 1) and charges or "")
                UpdateCooldown(b)
            end
        end
    end
end

-- outside combat: one button per visible quest row with an item, beside the
-- tracker on its outer edge (the left for a left-aligned tracker, else the right)
function mod.PlaceQuestItems()
    if InCombatLockdown() then
        if not pending then stats.waited = stats.waited + 1 end
        pending = true
        return
    end
    pending = false
    local f = _G.MMTQuestTrackerFrame
    local n = 0
    if Enabled() and f and f:IsShown() and f.rows then
        local ui = UIParent:GetEffectiveScale()
        local scale = f:GetEffectiveScale() / ui
        local right = M.db.align == "RIGHT"
        local edgeX = right and (f:GetRight() or 0) * scale or (f:GetLeft() or 0) * scale
        for _, row in ipairs(f.rows) do
            local e = row.entry
            if row:IsShown() and e and e.kind == "quest" and e.questID then
                local link, icon, charges, index = QuestItem(e.questID)
                local top, bottom = row:GetTop(), row:GetBottom()
                if link and top and bottom then
                    n = n + 1
                    local b = Button(n)
                    local size = math.max(16, math.floor((top - bottom) * scale + 6))
                    local cy = (top + bottom) / 2 * scale
                    b:SetSize(size, size)
                    b:ClearAllPoints()
                    if right then
                        b:SetPoint("LEFT", UIParent, "BOTTOMLEFT", edgeX + 3, cy)
                    else
                        b:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", edgeX - 3, cy)
                    end
                    local id = tonumber(link:match("item:(%d+)"))
                    b:SetAttribute("item", id and ("item:" .. id) or link)
                    b.questID, b.logIndex, b.link = e.questID, index, link
                    b.icon:SetTexture(icon)
                    b.count:SetText((charges and charges > 1) and charges or "")
                    UpdateCooldown(b)
                    b:Show()
                end
            end
        end
    end
    for i = n + 1, #pool do
        pool[i]:Hide()
        pool[i].questID = nil
    end
    placed = n
    stats.placed, stats.last = n, GetTime()
end

M:On("PLAYER_REGEN_ENABLED", function()
    if pending then mod.PlaceQuestItems() end
end)
M:On("BAG_UPDATE_COOLDOWN", function() mod.UpdateQuestItems() end)
M:On("QUEST_LOG_UPDATE", function() mod.UpdateQuestItems() end)

function mod.QuestItemsReport(add)
    local list = {}
    for i = 1, placed do
        local b = pool[i]
        if b and b.questID then list[#list + 1] = ("%d=%s"):format(b.questID, tostring(b.link)) end
    end
    add(("quest item buttons: on=%s placed=%d waiting for combat end=%s (%d)  %s"):format(
        tostring(M.db.questItems ~= false), placed, tostring(pending), stats.waited,
        #list > 0 and table.concat(list, ", ") or ""))
end
