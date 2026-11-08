-- MMT: mailbox and guild bank (Trade / Mail / Vendor page; as in EMA's Mail
-- and Guild modules, but with MMT's roles).
--
-- Mailbox: the "MMT Auto-Mailing" window next to the mail window lists the
-- mails "Mail to team" sends: every item in your bags that another team
-- member's role wants goes to that member (team order, as for trades; items
-- your own role wants stay), up to 12 items per mail; optionally the gold
-- above an amount goes to one team member. Each mail can be ticked off; the
-- postage is shown. The button is needed: one click sends all ticked mails
-- one after another.
--
-- Guild bank: a "Deposit" button next to the guild bank puts the items of
-- the chosen role (list) into the chosen tab, and optionally the gold above
-- an amount.

local _, ns = ...
local UI = ns.UI

local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12
local STEP = 0.25

local function Safe(fn, ...) if fn then return ns.Safe(fn, ...) end end

-- every bag item: bag, slot, link, info
local function BagItems()
    local list = {}
    for bag = 0, ns.BAGS do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.isLocked then
                list[#list + 1] = { bag = bag, slot = slot, link = info.hyperlink, info = info }
            end
        end
    end
    return list
end

-- a small button beside a Blizzard window (the window itself is not changed)
local function SideButton(name, text, onClick)
    local b = UI.Button(UIParent, 150, text, onClick)
    b:SetFrameStrata("HIGH")
    b:Hide()
    b.Place = function(anchor)
        b:ClearAllPoints()
        if anchor and anchor:IsShown() then b:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, -30)
        else b:SetPoint("TOP", UIParent, "TOP", 0, -120) end
        b:Show()
    end
    return b
end

local function InteractionType(name)
    return Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType[name]
end

---------------------------------------------------------------------------
-- Mail: the "MMT Auto-Mailing" window beside the mailbox
--
-- Shows the big "Mail to team" button, a table of the mails it would send
-- (to whom, for which role, how many items: a stack counts as one), each
-- with a tick to leave it out (all on whenever the mailbox opens), and the
-- postage for everything ticked. The table follows the bags while open.
---------------------------------------------------------------------------
local mailOpen = false
local queue        -- mails still to send: { { id, to, key, roles, items = {...}, money } }
local sending = false
local queued = 0   -- mails in this run (for "2 / 5")
local skip = {}    -- [mail id] = true: ticked off (until the mailbox closes)

-- postage of one mail: 30 copper per item attached, at least 30 (the game's
-- own figure is logged when a mail goes out, "mail: ... postage")
local POSTAGE = 30
local function Postage(mail)
    return POSTAGE * math.max(1, #mail.items)
end

-- the team member to mail an item to (nil: keep it), and the role that wants it
local function Recipient(link)
    local keys, roles = ns.MembersForItem(link)
    for _, key in ipairs(keys) do
        if ns.IsSelf(key) then return nil end   -- your own role wants it: keep
        return key, roles and roles[key]
    end
end

local function PlanMail()
    local cfg = ns.db.mail
    local byKey, order = {}, {}
    for _, it in ipairs(BagItems()) do
        local key, role
        if not it.info.isBound and not ns.ExcludedItem(it.link, "mail") then key, role = Recipient(it.link) end
        if key then
            it.role = role
            if not byKey[key] then byKey[key] = {}; order[#order + 1] = key end
            table.insert(byKey[key], it)
        end
    end
    local mails = {}
    for _, key in ipairs(order) do
        local items = byKey[key]
        local part = 0
        for i = 1, #items, MAX_ATTACH do
            part = part + 1
            local chunk, roles, seen = {}, {}, {}
            for j = i, math.min(i + MAX_ATTACH - 1, #items) do
                local it = items[j]
                chunk[#chunk + 1] = it
                if it.role and not seen[it.role] then seen[it.role] = true roles[#roles + 1] = it.role end
            end
            mails[#mails + 1] = { id = key .. "#" .. part, key = key, to = ns.WhisperTarget(key),
                roles = roles, items = chunk }
        end
    end
    -- gold above the amount to keep (after the postage of the ticked mails)
    local goldKey = cfg.goldTo ~= "" and ns.db.team[cfg.goldTo] and cfg.goldTo or nil
    if goldKey and not ns.IsSelf(goldKey) then
        local postage = POSTAGE
        for _, m in ipairs(mails) do if not skip[m.id] then postage = postage + Postage(m) end end
        local spare = GetMoney() - (cfg.keepGold or 0) * 10000 - postage
        if spare > 0 then
            mails[#mails + 1] = { id = "gold", key = goldKey, to = ns.WhisperTarget(goldKey), items = {}, money = spare }
        end
    end
    return mails
end
ns.PlanMail = PlanMail
function ns.MailSkip(id, off) skip[id] = off or nil end   -- for tests / the window

local Redraw   -- the window (below)

-- what was sent, one chat line at the end: "Mail to team: 3 items to John, 2g to Monika."
local sent = {}
local function SentText()
    local parts = {}
    for _, m in ipairs(sent) do parts[#parts + 1] = m.what .. " to " .. m.who end
    sent = {}
    return ns.AndList(parts)
end

local function SendNext()
    if not mailOpen or not queue or #queue == 0 then
        if queue and #queue == 0 then
            local text = SentText()
            ns.Print("Mail to team: %s.", text ~= "" and ("sent " .. text) or "done")
        elseif #sent > 0 then
            ns.Print("Mail to team: stopped (mailbox closed); sent %s.", SentText())
        end
        queue, sending = nil, false
        if Redraw then Redraw() end
        return
    end
    local mail = table.remove(queue, 1)
    sending = true
    local n = 0
    for _, it in ipairs(mail.items) do
        local info = C_Container.GetContainerItemInfo(it.bag, it.slot)
        if info and info.hyperlink == it.link then
            n = n + 1
            ClearCursor()
            C_Container.PickupContainerItem(it.bag, it.slot)
            ClickSendMailItemButton(n)
        end
    end
    if mail.money then SetSendMailMoney(mail.money) end
    if n == 0 and not mail.money then sending = false C_Timer.After(STEP, SendNext) return end
    local subject = mail.money and "MMT: gold" or ("MMT: " .. n .. (n == 1 and " item" or " items"))
    local price = Safe(GetSendMailPrice)
    local ok, err = pcall(SendMail, mail.to, subject, "")
    ns.Debug("mail: %s -> %s (%d items, %s copper) postage %s (estimate %d) %s %s", subject, ns.Repr(mail.to), n,
        tostring(mail.money or 0), tostring(price), Postage(mail), tostring(ok), tostring(err or ""))
    if ok then
        sent[#sent + 1] = { what = mail.money and ns.FormatMoney(mail.money) or (n .. (n == 1 and " item" or " items")), who = ns.ShownName(mail.key) }
    else
        sending = false
    end
    if Redraw then Redraw() end
end

ns.On("MAIL_SEND_SUCCESS", function() if sending then sending = false C_Timer.After(0.5, SendNext) end end)
ns.On("MAIL_FAILED", function()
    if sending then
        sending = false
        local text = #sent > 0 and SentText() or nil
        ns.Print("|cffff6666Mail to team: a mail could not be sent; stopped.|r%s", text and (" Sent before: " .. text .. ".") or "")
        queue = nil
        ClearSendMail()
        if Redraw then Redraw() end
    end
end)

local function StartMailing()
    if queue then return end
    local list = {}
    for _, m in ipairs(PlanMail()) do if not skip[m.id] then list[#list + 1] = m end end
    if #list == 0 then
        ns.Print("Mail to team: nothing to send (no items another team member's role wants, or all mails ticked off).")
        return
    end
    queue, queued = list, #list
    SendNext()
end

-- the window ---------------------------------------------------------------
local A = UI.ACCENT
local WIN_W, ROW_H, MAX_ROWS = 300, 20, 12
local COL_TO, COL_ROLE, COL_ITEMS = 30, 130, 248
local win, rows, plan

local function Row(i)
    rows = rows or {}
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, win.list)
    r:SetSize(WIN_W - 20, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    if i % 2 == 0 then UI.Fill(r, 1, 1, 1, 0.03) end
    local box = CreateFrame("Frame", nil, r)
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 6, 0)
    UI.Fill(box, 0.12, 0.12, 0.12, 1)
    UI.Border(box, 0.35, 0.35, 0.35, 1)
    r.mark = box:CreateTexture(nil, "ARTWORK")
    r.mark:SetPoint("TOPLEFT", 3, -3) r.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    r.mark:SetColorTexture(A[1], A[2], A[3], 1)
    r.to = UI.Label(r, "", "GameFontHighlightSmall")
    r.to:SetPoint("LEFT", COL_TO, 0) r.to:SetWidth(COL_ROLE - COL_TO - 4) r.to:SetJustifyH("LEFT") r.to:SetWordWrap(false)
    r.role = UI.Label(r, "", "GameFontHighlightSmall")
    r.role:SetPoint("LEFT", COL_ROLE, 0) r.role:SetWidth(COL_ITEMS - COL_ROLE - 4) r.role:SetJustifyH("LEFT") r.role:SetWordWrap(false)
    r.items = UI.Label(r, "", "GameFontHighlightSmall")
    r.items:SetPoint("RIGHT", -6, 0) r.items:SetJustifyH("RIGHT")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints() hl:SetColorTexture(1, 1, 1, 0.05)
    r:SetScript("OnClick", function(self)
        if queue or not self.mail then return end
        skip[self.mail.id] = not skip[self.mail.id] or nil
        Redraw()
    end)
    r:SetScript("OnEnter", function(self)
        if not self.mail then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.ShownName(self.mail.key))
        if self.mail.money then
            GameTooltip:AddLine(ns.FormatMoney(self.mail.money), 1, 1, 1)
        else
            for _, it in ipairs(self.mail.items) do
                local count = it.info.stackCount or 1
                GameTooltip:AddLine(it.link .. (count > 1 and (" x" .. count) or ""), 1, 1, 1)
            end
        end
        GameTooltip:AddLine("Click: send this mail or leave it out.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function BuildWindow()
    if win then return win end
    win = CreateFrame("Frame", "MMTMailWindow", UIParent)
    win:SetFrameStrata("HIGH")
    win:SetWidth(WIN_W)
    UI.Fill(win, 0.05, 0.05, 0.06, 0.94)
    UI.Border(win, A[1], A[2], A[3], 0.45)
    win:EnableMouse(true)
    win:Hide()
    local title = UI.Label(win, "MMT Auto-Mailing", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetTextColor(A[1], A[2], A[3])
    local line = win:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(A[1], A[2], A[3], 0.35)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 8, -32) line:SetPoint("TOPRIGHT", -8, -32)

    -- the big button
    local b = CreateFrame("Button", nil, win)
    b:SetSize(WIN_W - 20, 34)
    b:SetPoint("TOP", 0, -42)
    b.fill = UI.Fill(b, 0.10, 0.36, 0.16, 1)
    UI.Border(b, 0.35, 0.85, 0.45, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints() hl:SetColorTexture(1, 1, 1, 0.10)
    b.label = UI.Label(b, "Mail to team", "GameFontNormalLarge")
    b.label:SetPoint("CENTER")
    b.label:SetTextColor(1, 1, 1)
    b:SetScript("OnClick", StartMailing)
    UI.Tooltip(b, "Mail to team", "Sends the ticked mails below one after another: every item in your bags that another team member's role wants goes to that member (items your own role wants stay), 12 items per mail, and the gold above the amount to keep if set. Trade / Mail / Vendor page.")
    win.button = b

    -- the table
    local function Head(text, x, right)
        local h = UI.Label(win, text, "GameFontNormalSmall")
        if right then h:SetPoint("TOPRIGHT", win, "TOPRIGHT", -16, -86)
        else h:SetPoint("TOPLEFT", win, "TOPLEFT", 10 + x, -86) end
        h:SetTextColor(0.7, 0.7, 0.7)
        return h
    end
    Head("To", COL_TO) Head("Role", COL_ROLE) Head("Items", 0, true)
    win.list = CreateFrame("Frame", nil, win)
    win.list:SetPoint("TOPLEFT", 10, -102)
    win.list:SetSize(WIN_W - 20, ROW_H)
    win.empty = UI.Label(win.list, "Nothing to send: no items another team member's role wants.", "GameFontDisableSmall")
    win.empty:SetPoint("TOPLEFT", 6, -4) win.empty:SetWidth(WIN_W - 32) win.empty:SetJustifyH("LEFT")
    win.more = UI.Label(win, "", "GameFontDisableSmall")
    win.postage = UI.Label(win, "", "GameFontHighlight")
    win.status = UI.Label(win, "", "GameFontDisableSmall")
    return win
end

function Redraw()
    if not win or not win:IsShown() then return end
    plan = queue and plan or PlanMail()
    local shown, postage, on = 0, 0, 0
    for i, m in ipairs(plan) do
        if i <= MAX_ROWS then
            local r = Row(i)
            r.mail = m
            r.mark:SetShown(not skip[m.id])
            r.to:SetText(ns.ShownName(m.key))
            if m.money then
                r.role:SetText("Gold")
                r.items:SetText(ns.FormatMoney(m.money))
            else
                r.role:SetText(table.concat(m.roles or {}, ", "))
                r.items:SetText(tostring(#m.items))
            end
            local a = skip[m.id] and 0.45 or 1
            r.to:SetAlpha(a) r.role:SetAlpha(a) r.items:SetAlpha(a)
            r:Show()
            shown = i
        end
        if not skip[m.id] then on = on + 1 postage = postage + Postage(m) end
    end
    for i = shown + 1, #(rows or {}) do rows[i]:Hide() rows[i].mail = nil end
    win.empty:SetShown(#plan == 0)
    local listH = math.max(1, shown) * ROW_H
    win.list:SetHeight(listH)
    local y = -102 - listH - 6
    if #plan > MAX_ROWS then
        win.more:SetText(("+ %d more mails (sent too unless all of them are ticked off)"):format(#plan - MAX_ROWS))
        win.more:ClearAllPoints() win.more:SetPoint("TOPLEFT", 16, y) win.more:Show()
        y = y - 16
    else
        win.more:Hide()
    end
    win.postage:ClearAllPoints() win.postage:SetPoint("TOPLEFT", 16, y - 2)
    win.postage:SetText(("Postage: %s  (%d of %d %s)"):format(ns.FormatMoney(postage), on, #plan, #plan == 1 and "mail" or "mails"))
    y = y - 20
    win.status:ClearAllPoints() win.status:SetPoint("TOPLEFT", 16, y)
    if queue then
        win.status:SetText(("Sending %d / %d ..."):format(queued - #queue, queued))
        win.status:Show() y = y - 16
    else
        win.status:Hide()
    end
    win:SetHeight(-y + 8)
    local busy = queue ~= nil
    win.button:SetAlpha((busy or on == 0) and 0.5 or 1)
    win.button.label:SetText(busy and "Sending ..." or "Mail to team")
end

local function PlaceWindow()
    BuildWindow()
    win:ClearAllPoints()
    local anchor = _G.MailFrame
    if anchor and anchor:IsShown() then win:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    else win:SetPoint("TOP", UIParent, "TOP", 0, -120) end
    win:Show()
    Redraw()
end

local function MailShown()
    mailOpen = true
    if ns.db.mail.enabled then PlaceWindow() end
end
local function MailHidden()
    mailOpen, queue, sending = false, nil, false
    skip = {}
    if win then win:Hide() end
end
ns.On("MAIL_SHOW", MailShown)
ns.On("MAIL_CLOSED", MailHidden)
-- the bags change: the table follows (not while sending; it shows the run)
local redrawSoon = ns.Coalesce and ns.Coalesce(function() if not queue then plan = nil Redraw() end end, 0.3)
ns.On("BAG_UPDATE_DELAYED", function() if redrawSoon and win and win:IsShown() then redrawSoon() end end)
ns.On("PLAYER_MONEY", function() if redrawSoon and win and win:IsShown() then redrawSoon() end end)
-- settings changed (switched on / off, gold): show, hide, look again
ns.Listen("REFRESH", function()
    if not mailOpen then return end
    if not ns.db.mail.enabled then if win then win:Hide() end return end
    if not (win and win:IsShown()) then PlaceWindow() elseif not queue then Redraw() end
end)

---------------------------------------------------------------------------
-- Guild bank
---------------------------------------------------------------------------
local bankOpen = false

local function DepositAll()
    local cfg = ns.db.gbank
    local role = cfg.role ~= "" and ns.db.roles[cfg.role] and cfg.role or nil
    local items = {}
    if role then
        for _, it in ipairs(BagItems()) do
            if not it.info.isBound and ns.RoleWantsItem(role, it.link) then items[#items + 1] = it end
        end
    end
    if SetCurrentGuildBankTab then pcall(SetCurrentGuildBankTab, cfg.tab or 1) end
    local i = 0
    local deposited = {}
    local function Next()
        i = i + 1
        local it = items[i]
        if not it or not bankOpen then
            if cfg.gold and bankOpen and DepositGuildBankMoney then
                local spare = GetMoney() - (cfg.keepGold or 0) * 10000
                if spare > 0 then
                    pcall(DepositGuildBankMoney, spare)
                    deposited[#deposited + 1] = ns.FormatMoney(spare)
                end
            end
            if #items > 0 then deposited[#deposited + 1] = ("%d %s into tab %d"):format(#items, #items == 1 and "item" or "items", cfg.tab or 1) end
            if #deposited > 0 then ns.Print("Guild bank: deposited %s.", ns.AndList(deposited)) end
            return
        end
        local info = C_Container.GetContainerItemInfo(it.bag, it.slot)
        if info and info.hyperlink == it.link then C_Container.UseContainerItem(it.bag, it.slot) end
        C_Timer.After(STEP, Next)
    end
    if #items == 0 and not cfg.gold then
        ns.Print("Guild bank: nothing to deposit (choose a role on the Trade / Mail / Vendor page).")
        return
    end
    Next()
end

local bankButton = SideButton("MMTGuildBankButton", "Deposit to guild bank", DepositAll)
UI.Tooltip(bankButton, "Deposit to guild bank", "Puts the items of the chosen role into the chosen tab, and the gold above the amount to keep if set. Trade / Mail / Vendor page.")

local function BankShown()
    bankOpen = true
    if ns.db.gbank.enabled then C_Timer.After(0.2, function() if bankOpen then bankButton.Place(_G.GuildBankFrame) end end) end
end
local function BankHidden()
    bankOpen = false
    bankButton:Hide()
end
ns.On("GUILDBANKFRAME_OPENED", BankShown)
ns.On("GUILDBANKFRAME_CLOSED", BankHidden)

-- retail: frames opened by NPC interaction
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
    if kind == InteractionType("GuildBanker") then BankShown()
    elseif kind == InteractionType("MailInfo") then MailShown() end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind)
    if kind == InteractionType("GuildBanker") then BankHidden()
    elseif kind == InteractionType("MailInfo") then MailHidden() end
end)
