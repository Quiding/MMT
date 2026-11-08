-- MMT: at a vendor: repair, sell grey items and the items of the sell list,
-- never the items of the never-sell list, and buy the items of the buy list
-- up to their count (Trade / Mail / Vendor page).
--
-- The sell and never-sell lists are roles (Roles page): all their items and
-- rules (item, quality, Bind on Equip, item group) count.

local _, ns = ...

local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
local BATCH, INTERVAL = 10, 0.2

local merchantOpen = false
local ticker

local function SellPrice(info)
    local price = select(11, ns.ItemInfo(info.hyperlink or info.itemID))
    return price or 0
end

-- role of the list, or nil when none is chosen / the role was deleted
local function ListRole(name)
    if name and name ~= "" and ns.db.roles[name] then return name end
end

-- should this bag item be sold?
local function ToSell(info)
    local m = ns.db.merchant
    local link = info.hyperlink or info.itemID
    local never = ListRole(m.neverRole)
    if never and ns.RoleWantsItem(never, link) then return false end
    if m.sellGrey and info.quality == POOR then return true end
    local sell = ListRole(m.sellRole)
    return sell ~= nil and ns.RoleWantsItem(sell, link)
end

local function CollectJunk()
    local list = {}
    for bag = 0, ns.BAGS do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and not info.hasNoValue and not info.isLocked and ToSell(info) then
                local price = SellPrice(info)
                if price > 0 then
                    list[#list + 1] = {
                        bag = bag, slot = slot, itemID = info.itemID,
                        count = info.stackCount or 1,
                        value = price * (info.stackCount or 1),
                    }
                end
            end
        end
    end
    return list
end

-- tell the leader's chat (another character's client)
local function Tell(msg)
    if ns.db.merchant.tellLeader and ns.TellLeader then ns.TellLeader(msg) end
end

---------------------------------------------------------------------------
-- Chat: one line per character and vendor visit
--   Vendor: John sold 12 items for 1g 20s and repaired for 3g 10s
-- r = { sold = { count, value }, repair = { cost, how = "o"|"g"|"x" },
--       bought = { "20 x Water", ... }, short = { "20 x Water", ... } }
---------------------------------------------------------------------------
local RED = "|cffff6666"
local function VisitLine(who, r, reportOn)
    local parts = {}
    if r.sold and reportOn then
        local n = r.sold[1]
        parts[#parts + 1] = ("sold %d %s for %s"):format(n, n == 1 and "item" or "items", ns.FormatMoney(r.sold[2]))
    end
    if r.repair then
        if r.repair.how == "x" then
            parts[#parts + 1] = RED .. ("couldn't repair (%s needed)"):format(ns.FormatMoney(r.repair.cost)) .. "|r"
        elseif reportOn then
            parts[#parts + 1] = ("repaired for %s%s"):format(ns.FormatMoney(r.repair.cost), r.repair.how == "g" and " (guild bank)" or "")
        end
    end
    if r.bought and #r.bought > 0 and reportOn then parts[#parts + 1] = "bought " .. table.concat(r.bought, ", ") end
    if r.short and #r.short > 0 then
        parts[#parts + 1] = RED .. "not enough money to buy " .. table.concat(r.short, ", ") .. "|r"
    end
    if #parts == 0 then return end
    ns.Print("Vendor: %s %s", who, ns.AndList(parts))
end

-- this character: collected while selling / repairing / buying, printed when all is done
local own, ownGen = nil, 0
local function OwnVisit()
    own = own or {}
    return own
end
local ownTicker   -- the sell ticker (below) still running: wait
local function OwnFlush()
    ownGen = ownGen + 1
    local mine = ownGen
    C_Timer.After(1, function()
        if mine ~= ownGen or not own then return end
        if ownTicker and ownTicker() then OwnFlush() return end   -- still selling
        local r = own
        own = nil
        VisitLine(ns.ShownName(ns.PlayerFull()), r, ns.db.merchant.report)
    end)
end

local function Report(count, value)
    if count == 0 then return end
    OwnVisit().sold = { count, value }
    OwnFlush()
    Tell(("NOTE:SELL:%d:%d"):format(count, value))
end

ownTicker = function() return ticker ~= nil end

local function SellGrey()
    if ticker then return end
    local list = CollectJunk()
    if #list == 0 then return end

    local index, count, value = 1, 0, 0
    ticker = C_Timer.NewTicker(INTERVAL, function(self)
        for _ = 1, BATCH do
            local item = list[index]
            if not item or not merchantOpen then
                self:Cancel()
                ticker = nil
                Report(count, value)
                return
            end
            index = index + 1
            if C_Container.GetContainerItemID(item.bag, item.slot) == item.itemID then
                C_Container.UseContainerItem(item.bag, item.slot)
                count = count + item.count
                value = value + item.value
            end
        end
    end)
end

local function Repair()
    if not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end

    local m = ns.db.merchant
    if m.guildRepair and CanGuildBankRepair and CanGuildBankRepair() then
        local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
        if limit == -1 or limit >= cost then
            RepairAllItems(true)
            OwnVisit().repair = { cost = cost, how = "g" } OwnFlush()
            Tell(("NOTE:REPAIR:%d:g"):format(cost))
            return
        end
    end

    if GetMoney() < cost then
        OwnVisit().repair = { cost = cost, how = "x" } OwnFlush()
        Tell(("NOTE:REPAIR:%d:x"):format(cost))
        return
    end
    RepairAllItems()
    OwnVisit().repair = { cost = cost, how = "o" } OwnFlush()
    Tell(("NOTE:REPAIR:%d:o"):format(cost))
end

---------------------------------------------------------------------------
-- Buy list: { itemID, name, count, who } bought up to count (who: only that
-- character, nil = every character)
---------------------------------------------------------------------------
local function MerchantItem(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if info then return info.name, info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
    end
    if GetMerchantItemInfo then
        local name, _, price, stack, available, _, _, extended = GetMerchantItemInfo(i)
        return name, price, stack, available, extended
    end
end

local function ItemCount(id)
    local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id)) or 0
    return count
end

-- buy list entry: the characters it is for (a list of team keys), nil = every character
function ns.BuyEntryChars(entry)
    if type(entry.chars) == "table" and #entry.chars > 0 then return entry.chars end
    if type(entry.who) == "string" and entry.who ~= "" then return { entry.who } end   -- before 0.9.60
    return nil
end

-- is the entry for this character?
function ns.BuyEntryFor(entry, key)
    local chars = ns.BuyEntryChars(entry)
    if not chars then return true end
    for _, k in ipairs(chars) do
        if ns.IsSelf(k) or (key and ns.NormKey(k) == ns.NormKey(key)) then return true end
    end
    return false
end

local function BuyList()
    local m = ns.db.merchant
    if not m.buy then return end
    local bought = {}
    for _, entry in ipairs(m.buyList or {}) do
        local id, want = entry.itemID, entry.count or 0
        -- an item for some characters is bought only on those
        if not ns.BuyEntryFor(entry, ns.PlayerFull()) then id = nil end
        local need = id and (want - ItemCount(id)) or 0
        if need > 0 then
            for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
                if GetMerchantItemID and GetMerchantItemID(i) == id then
                    local name, price, stack, available, extended = MerchantItem(i)
                    stack = (stack and stack > 0) and stack or 1
                    if extended then break end   -- costs something other than gold
                    if available and available >= 0 then need = math.min(need, available * stack) end
                    local cost = math.ceil(need / stack) * (price or 0)
                    if cost > GetMoney() then
                        local v = OwnVisit()
                        v.short = v.short or {}
                        v.short[#v.short + 1] = ("%d x %s"):format(need, name or ("item " .. id))
                        break
                    end
                    -- the game sells at most one max stack per call
                    local max = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(i)) or need
                    local left = need
                    while left > 0 do
                        local n = math.min(left, max)
                        pcall(BuyMerchantItem, i, n)
                        left = left - n
                    end
                    bought[#bought + 1] = ("%d x %s"):format(need, name or ("item " .. id))
                    break
                end
            end
        end
    end
    if #bought > 0 then OwnVisit().bought = bought end
    if own then OwnFlush() end
end

ns.On("MERCHANT_SHOW", function()
    merchantOpen = true
    local m = ns.db.merchant
    if m.repair then Repair() end
    if m.sellGrey or ListRole(m.sellRole) then SellGrey() end
    if m.buy then C_Timer.After(0.5, function() if merchantOpen then BuyList() end end) end
end)

ns.On("MERCHANT_CLOSED", function()
    merchantOpen = false
end)

-- the leader's client: notes from the team (NOTE:SELL and NOTE:REPAIR), one line
-- per character: when both arrived, else 4 seconds after the first
local visits = {}   -- [key] = { r, gen }
local function TeamFlush(key)
    local v = visits[key]
    visits[key] = nil
    if v then VisitLine(ns.ShownName(key), v.r, true) end
end
ns.Listen("TEAM_MESSAGE", function(key, sender, text, _, channel)
    local kind, a, b = text:match("^NOTE:(%u+):(%d+):?(%w*)")
    if not (kind == "SELL" or kind == "REPAIR") or not ns.AcceptNotice(channel) then return end
    local v = visits[key]
    if not v then
        v = { r = {} }
        visits[key] = v
        C_Timer.After(4, function() if visits[key] == v then TeamFlush(key) end end)
    end
    if kind == "SELL" then
        v.r.sold = { tonumber(a) or 0, tonumber(b) or 0 }
    else
        v.r.repair = { cost = tonumber(a) or 0, how = (b == "x" or b == "g") and b or "o" }
    end
    if v.r.sold and v.r.repair then TeamFlush(key) end
end)
