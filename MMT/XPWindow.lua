-- MMT: vertical, movable window with XP %, rested XP %, layer and phasing
-- of every online team member. Offline members are hidden. What a row shows
-- besides the name and the bar are pieces (XPPieces.lua), in the player's order;
-- /mmt xp arrange drags them (and the rows) into place.

local _, ns = ...

local PAD = 3
local function Gap() return ns.db.xp.rowGap or 3 end
local A = { 0.31, 0.70, 1.00 }

local f = CreateFrame("Frame", "MMTXPFrame", UIParent)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:SetMovable(true)
f:RegisterForDrag("LeftButton")
f:Hide()
f.bg = f:CreateTexture(nil, "BACKGROUND")
f.bg:SetAllPoints()
f.rows = {}

-- moving: Shift + drag, or the move tab (unless locked)
local dragging, dragEnd = false, 0
f:SetScript("OnDragStart", function(self)
    if ns.db.xp.locked or not IsShiftKeyDown() then return end
    dragging = true
    self:StartMoving()
end)
f:SetScript("OnDragStop", function(self)
    if not dragging then return end
    dragging, dragEnd = false, GetTime()
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    ns.db.xp.point = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
end)
-- the window's own border / background: right-click = settings
f:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and GetTime() - dragEnd > 0.2 then ns.ToggleConfig("xp") end
end)

-- move tab above the top-left corner: while unlocked, it shows when the mouse is over the
-- window (always while arranging); dragging it moves the window, no Shift needed
local handle = CreateFrame("Frame", nil, f)
handle:SetSize(40, 12)
handle:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0)
handle.bg = handle:CreateTexture(nil, "BACKGROUND")
handle.bg:SetAllPoints()
handle.bg:SetColorTexture(0, 0, 0, 0.6)
handle.line = handle:CreateTexture(nil, "BORDER")
handle.line:SetPoint("TOPLEFT"); handle.line:SetPoint("TOPRIGHT")
handle.line:SetHeight(1)
handle.line:SetColorTexture(A[1], A[2], A[3], 0.8)
for c = 0, 4 do
    for r = 0, 1 do
        local d = handle:CreateTexture(nil, "ARTWORK")
        d:SetSize(2, 2)
        d:SetPoint("CENTER", (c - 2) * 5, r == 0 and 2 or -2)
        d:SetColorTexture(1, 1, 1, 0.8)
    end
end
handle:EnableMouse(true)
handle:RegisterForDrag("LeftButton")
handle:SetScript("OnDragStart", function()
    if ns.db.xp.locked then return end
    dragging = true
    f:StartMoving()
end)
handle:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
handle:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("XP window")
    GameTooltip:AddLine("Drag to move it. Lock its position on the XP Window page.", 1, 1, 1, true)
    GameTooltip:Show()
end)
handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
handle:Hide()
f.handle = handle

local function HandleWanted()
    if ns.db.xp.locked then return false end
    return dragging or ns.xpArrange or f:IsMouseOver(14, 0, 0, 0) or handle:IsMouseOver()
end
local handleCheck = 0
f:SetScript("OnUpdate", function(_, elapsed)
    handleCheck = handleCheck + elapsed
    if handleCheck < 0.15 then return end
    handleCheck = 0
    handle:SetShown(HandleWanted() and true or false)
end)

---------------------------------------------------------------------------
-- Row actions
--   click: FTL leader   right-click: invite   middle-click: invite the team
--   Ctrl-click: inspect   Ctrl-right-click: talents
--   Shift + drag: move   Shift-right-click: settings
---------------------------------------------------------------------------
local function GroupUnit(key)
    if ns.IsSelf(key) then return "player" end
    return ns.UnitForMember(key)
end

local function CanLead()
    return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function Invite(key)
    if ns.IsSelf(key) then return end
    if ns.UnitForMember(key) then ns.Print("%s is already in your group.", ns.FullDisplay(key)) return end
    if not CanLead() then ns.Print("Only the group leader can invite.") return end
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    local ok, err = pcall(invite, ns.WhisperTarget(key))
    ns.Debug("XP window invite %s -> %s %s", ns.Repr(ns.WhisperTarget(key)), tostring(ok), tostring(err or ""))
    if ok then ns.Print("Invited %s.", ns.FullDisplay(key)) end
end

-- middle-click: invite every team member who isn't in the group yet
local function InviteTeam()
    if not CanLead() then ns.Print("Only the group leader can invite.") return end
    local n = 0
    for _, key in ipairs(ns.SortedMembers()) do
        if not ns.IsSelf(key) and not ns.UnitForMember(key) then
            local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
            if pcall(invite, ns.WhisperTarget(key)) then n = n + 1 end
        end
    end
    if n > 0 then ns.Print("Invited %d team member(s).", n) else ns.Print("The whole team is in your group already.") end
end

local function MakeLeader(key)
    if not ns.db.ftl.enabled then ns.Print("FTL is switched off (/mmt > FTL).") return end
    ns.SetFTLLeader(key)
end

-- Blizzard windows are only opened outside combat (opening them from addon
-- code in combat can trigger the "blocked action" message)
local function NotInCombat()
    if InCombatLockdown() then ns.Print("Not in combat.") return false end
    return true
end

-- Forever's unit menu has "View Talents" (below "Inspect"), which opens the
-- talents in their own window. The menu entry is a UnitPopup button mixin;
-- MMT finds it by name and calls its OnClick the way the menu does. Fallback:
-- inspect, then the inspect window's Talents button / tab.
local talentMixin

local function FindTalentMixin()
    if talentMixin then return talentMixin end   -- only a find is kept (the menu code may load later)
    local names = {}
    for name, v in pairs(_G) do
        if type(name) == "string" and type(v) == "table" and name:find("^UnitPopup") and name:find("Talent")
            and type(rawget(v, "OnClick")) == "function" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    -- prefer "View..." / "Inspect..." over others
    for _, name in ipairs(names) do
        if name:find("View") or name:find("Inspect") then talentMixin = _G[name] break end
    end
    talentMixin = talentMixin or (names[1] and _G[names[1]])
    ns.Debug("talent view: menu entries %s -> %s", table.concat(names, ", "), tostring(#names > 0))
    return talentMixin
end

-- debug: every global name about talents / inspect (/mmt debug talents)
function ns.ListTalentGlobals()
    local out = {}
    for name, v in pairs(_G) do
        if type(name) == "string" and #out < 300 and (name:find("Talent") or name:find("Inspect")
            or (name:find("^UnitPopup") and name:find("Mixin$"))) then
            out[#out + 1] = name .. " (" .. type(v) .. ")"
        end
    end
    table.sort(out)
    return out
end

local function ClickTalentsButton(frame, depth)
    if not frame or depth > 4 or not frame.GetChildren then return false end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child.IsShown and child:IsShown() and child.GetText and child.Click then
            local text = child:GetText()
            if type(text) == "string" and not ns.IsSecret(text)
                and (text == (TALENTS or "Talents") or text:lower():find("talent", 1, true)) then
                pcall(child.Click, child)
                ns.Debug("talent view: clicked %s (%s)", child:GetName() or "button", text)
                return true
            end
        end
        if ClickTalentsButton(child, depth + 1) then return true end
    end
    return false
end

local function ViewTalents(unit, key)
    local mixin = FindTalentMixin()
    if mixin then
        local ctx = { unit = unit, name = GetUnitName(unit, true), guid = UnitGUID(unit) }
        local ok, err = pcall(mixin.OnClick, mixin, ctx)
        ns.Debug("talent view: menu entry OnClick(%s) -> %s %s", unit, tostring(ok), tostring(err or ""))
        if ok then return end
    end
    -- fallback: inspect window, then its Talents button / tab
    local ok, err = pcall(InspectUnit, unit)
    ns.Debug("InspectUnit(%s) -> %s %s", unit, tostring(ok), tostring(err or ""))
    if not ok then return end
    C_Timer.After(0.6, function()
        if ClickTalentsButton(InspectFrame, 0) then return end
        if InspectFrameTab3 and InspectFrameTab3:IsShown() then pcall(InspectFrameTab3.Click, InspectFrameTab3) return end
        ns.Debug("talent view: no Talents button found; /mmt debug talents lists candidates")
        ns.Print("Couldn't open the talents of %s. Please run /mmt debug talents and send me the report.", ns.FullDisplay(key))
    end)
end

local function Inspect(key, talents)
    if not NotInCombat() then return end
    if ns.IsSelf(key) then
        if talents then
            if ToggleTalentFrame then pcall(ToggleTalentFrame)
            elseif PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then pcall(PlayerSpellsUtil.ToggleClassTalentFrame) end
        elseif ToggleCharacter then
            pcall(ToggleCharacter, "PaperDollFrame")
        end
        return
    end
    local unit = GroupUnit(key)
    if not unit then ns.Print("%s must be in your group to be inspected.", ns.FullDisplay(key)) return end
    if CanInspect and not CanInspect(unit) then ns.Print("%s is too far away to inspect.", ns.FullDisplay(key)) return end
    if not InspectUnit then return end
    if talents then ViewTalents(unit, key) return end
    local ok, err = pcall(InspectUnit, unit)
    ns.Debug("InspectUnit(%s) -> %s %s", unit, tostring(ok), tostring(err or ""))
end

local function RowClick(row, button)
    local key = row.key
    if not key or dragging or GetTime() - dragEnd < 0.2 then return end
    if ns.xpArrange then return end                -- arranging: rows are dragged, not clicked
    local shift, ctrl = IsShiftKeyDown(), IsControlKeyDown()
    if button == "MiddleButton" then InviteTeam() return end
    if button == "RightButton" and shift then ns.ToggleConfig("xp") return end
    if shift then return end                      -- Shift + drag moves the window
    if button == "LeftButton" then
        if ctrl then Inspect(key, false) else MakeLeader(key) end
    elseif button == "RightButton" then
        if ctrl then Inspect(key, true) else Invite(key) end
    end
end

-- mouseover on a row: full name and all details of that member
local function RowTooltip(row)
    local key, s = row.key, row.status
    if not key or not s then return end
    local tip = ns.MemberTooltip(row, key, "ANCHOR_RIGHT")
    tip:AddLine(" ")
    if s.isMax or s.max <= 0 then
        tip:AddDoubleLine("Level " .. s.level, "max level", 1, 1, 1, 0.7, 0.7, 0.7)
    else
        tip:AddDoubleLine("Level " .. s.level, ("%d / %d XP (%.1f%%)"):format(s.cur, s.max, s.cur / s.max * 100), 1, 1, 1, 1, 1, 1)
        if s.rested > 0 then
            tip:AddDoubleLine("Rested", ("%d XP (%d%%)"):format(s.rested, math.floor(s.rested / s.max * 100 + 0.5)), 0.75, 0.6, 1, 0.75, 0.6, 1)
        end
    end
    if s.money then tip:AddDoubleLine("Gold", GetCoinTextureString and GetCoinTextureString(s.money) or ns.FormatMoney(s.money), 1, 1, 1, 1, 1, 1) end
    if s.free then tip:AddDoubleLine("Bags", ("%d of %d slots free"):format(s.free, s.slots or 0), 1, 1, 1, 1, 1, 1) end
    if s.durMin then
        tip:AddDoubleLine("Durability", ("lowest %d%%, average %d%%"):format(s.durMin, s.durAvg or s.durMin), 1, 1, 1, 1, 1, 1)
    end
    if s.rep then
        local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[s.rep.standing]
        local standing = _G["FACTION_STANDING_LABEL" .. tostring(s.rep.standing)] or ""
        tip:AddDoubleLine(s.rep.name, ("%s  %d / %d"):format(standing, s.rep.cur or 0, s.rep.max or 0),
            1, 1, 1, c and c.r or 1, c and c.g or 1, c and c.b or 1)
    end
    tip:AddDoubleLine("Layer", s.layer and ("#" .. s.layer) or "unknown", 1, 1, 1, 0.7, 0.7, 0.7)
    local phase = ns.PhaseOf(key)
    if phase then tip:AddDoubleLine("Phasing", phase, 1, 1, 1, 1, 0.25, 0.25) end
    if ns.db.xp.followCheck then
        local fi = ns.FollowInfo(key)
        if fi and fi.broken then
            tip:AddDoubleLine("Follow", "stopped following " .. ns.Ago(time() - math.floor(GetTime() - (fi.since or GetTime()))), 1, 1, 1, 1, 0.3, 0.3)
        elseif fi and fi.combatBreak then
            tip:AddDoubleLine("Follow", "broke in combat", 1, 1, 1, 1, 0.85, 0.2)
        elseif fi and fi.following then
            local t = fi.targetKey and ns.FullDisplay(fi.targetKey) or fi.target
            tip:AddDoubleLine("Follow", t and ("following " .. t) or "following", 1, 1, 1, 0.4, 1, 0.4)
        end
    end
    local cc = ns.db.cc.enabled and ns.CCState and ns.CCState(key)
    if cc then
        local left, spell = ns.CCLeft(cc), ns.CCSpellName(cc)
        tip:AddDoubleLine("Control", ns.CCLabel(cc.kind) .. (left and (", " .. left .. " s") or "") .. (spell and (" (" .. spell .. ")") or ""),
            1, 1, 1, 1, 0.6, 0.1)
    end
    if ns.IsFTLLeader(key) then tip:AddLine("FTL leader: {FTL} macros point to this character.", 1, 0.82, 0) end
    tip:AddLine(" ")
    if ns.xpArrange then
        tip:AddLine("Arranging: drag the row up or down, or a piece along it. /mmt xp arrange to stop.", 0.5, 0.5, 0.5, true)
        tip:Show()
        return
    end
    tip:AddLine("Click: make FTL leader   Right-click: invite", 0.5, 0.5, 0.5)
    tip:AddLine(ns.IsSelf(key) and "Ctrl-click: character   Ctrl-right-click: talents"
        or "Ctrl-click: inspect   Ctrl-right-click: talents", 0.5, 0.5, 0.5)
    tip:AddLine("Middle-click: invite the whole team", 0.5, 0.5, 0.5)
    tip:AddLine((ns.db.xp.locked and "" or "Shift-drag or the tab above: move   ") .. "Shift-right-click: settings", 0.5, 0.5, 0.5)
    tip:Show()
end

---------------------------------------------------------------------------
-- Arranging (ns.xpArrange, session only: /mmt xp arrange, XP Window page):
-- every switched-on piece shows with dots and can be dragged along its row,
-- also to the other side of the bar's start (XPPieces.lua keeps the order);
-- a row dragged up or down changes the team order.
---------------------------------------------------------------------------
local drag   -- { kind = "piece", id, row } | { kind = "row", key }
local driver = CreateFrame("Frame")
driver:Hide()
local marker = CreateFrame("Frame", nil, f)
marker:SetFrameLevel(f:GetFrameLevel() + 30)
marker.tex = marker:CreateTexture(nil, "OVERLAY")
marker.tex:SetAllPoints()
marker.tex:SetColorTexture(1, 0.82, 0, 1)
marker:Hide()

local function PieceGap() return math.max(4, math.floor(ns.db.xp.size * 0.5)) end
local NAME_ROOM = 60   -- the name always gets at least this much of the bar
local rowWidth = 325   -- the rows' width at the last redraw: the set width, or more when the pieces need it

local function Cursor()
    local scale = f:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    return cx / scale, cy / scale
end

-- the piece a dragged one would go before (nil: the end of that side)
local function PieceTarget(d)
    local row = d.row
    local cx = Cursor()
    local barLeft = row.bar:GetLeft()
    if not barLeft then return end
    local side = (cx < barLeft) and "LEFT" or "RIGHT"
    local frames = {}
    for _, p in ipairs(row.pieces) do
        if p:IsShown() and p.id and p.side == side then frames[#frames + 1] = p end
    end
    table.sort(frames, function(a, b) return (a:GetLeft() or 0) < (b:GetLeft() or 0) end)
    for _, p in ipairs(frames) do
        local l, r = p:GetLeft(), p:GetRight()
        if l and r and cx < (l + r) / 2 then return side, p.id, p, frames end
    end
    return side, nil, nil, frames
end

local function PieceNoMove(d, side, beforeId)
    if beforeId == d.id then return true end
    local next, seen, mine
    for _, q in ipairs(ns.XPPieceOrder()) do
        if q.id == d.id then seen, mine = true, q
        elseif seen and q.side == side and q.on and ns.xpPieces[q.id] then next = q.id break end
    end
    return mine and mine.side == side and next == beforeId
end

-- the row a dragged one would go above (nil: below the last)
local function RowTarget()
    local _, cy = Cursor()
    local last
    for _, row in ipairs(f.rows) do
        if row:IsShown() and row.key then
            local t, b = row:GetTop(), row:GetBottom()
            if t and b and cy > (t + b) / 2 then return row.key, row end
            last = row
        end
    end
    return nil, nil, last
end

local function RowNoMove(d, beforeKey)
    if beforeKey == d.key then return true end
    local seen
    for _, row in ipairs(f.rows) do
        if row:IsShown() and row.key then
            if seen then return row.key == beforeKey end
            if row.key == d.key then seen = true end
        end
    end
    return beforeKey == nil
end

local function ShowMarker()
    local d = drag
    marker:ClearAllPoints()
    local x = ns.db.xp
    local h = math.max(x.barHeight, x.size + 4)
    if d.kind == "piece" then
        local side, beforeId, p, frames = PieceTarget(d)
        if not side or PieceNoMove(d, side, beforeId) then marker:Hide() return end
        local half = PieceGap() / 2
        marker:SetSize(2, h)
        if p then
            marker:SetPoint("CENTER", p, "LEFT", -half, 0)
        elseif #frames > 0 then
            marker:SetPoint("CENTER", frames[#frames], "RIGHT", half, 0)
        elseif side == "LEFT" then
            marker:SetPoint("LEFT", d.row, "LEFT", 2, 0)
        else
            marker:SetPoint("RIGHT", d.row.bar, "RIGHT", -2, 0)
        end
    else
        local beforeKey, row, last = RowTarget()
        if RowNoMove(d, beforeKey) or not (row or last) then marker:Hide() return end
        local half = Gap() / 2
        marker:SetSize(rowWidth, 2)
        if row then marker:SetPoint("CENTER", row, "TOP", 0, half)
        else marker:SetPoint("CENTER", last, "BOTTOM", 0, -half) end
    end
    marker:Show()
end

local function EndDrag()
    local d = drag
    if not d then return end
    drag = nil
    driver:Hide()
    marker:Hide()
    if d.kind == "piece" then
        local side, beforeId = PieceTarget(d)
        if side and not PieceNoMove(d, side, beforeId) then ns.MoveXPPiece(d.id, side, beforeId) return end
    else
        local beforeKey = RowTarget()
        if not RowNoMove(d, beforeKey) then ns.MoveMemberBefore(d.key, beforeKey) return end
    end
    ns.UpdateXPWindow()   -- undim
end

driver:SetScript("OnUpdate", function()
    if not drag then driver:Hide() return end
    if not IsMouseButtonDown("LeftButton") then EndDrag() return end
    ShowMarker()
end)

local function StartDrag(d)
    GameTooltip:Hide()
    drag = d
    ns.UpdateXPWindow()   -- dims it
    driver:Show()
end

function ns.ToggleXPArrange(on)
    if on == nil then on = not ns.xpArrange end
    ns.xpArrange = on and true or nil
    if on and not ns.db.xp.enabled then ns.Print("The XP window is hidden: /mmt xp shows it.") end
    ns.Print(on and "XP window: arranging. Drag a piece along its row (also across to the other side), or a row up or down. /mmt xp arrange again to stop."
        or "XP window: arranging off.")
    ns.Refresh()
end

local function DotGrip(parent)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(6, 10)
    for c = 0, 1 do
        for r = 0, 2 do
            local d = g:CreateTexture(nil, "OVERLAY")
            d:SetSize(2, 2)
            d:SetPoint("TOPLEFT", c * 4, -r * 4)
            d:SetColorTexture(1, 1, 1, 0.9)
        end
    end
    return g
end

-- one piece of a row: its own frame, so it can be dragged while arranging
local function PieceFrame(row, n)
    local p = row.pieces[n]
    if p then return p end
    p = CreateFrame("Frame", nil, row)
    p:SetFrameLevel(row:GetFrameLevel() + 4)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    p.bg:SetColorTexture(0, 0, 0, 0.55)
    p.grip = DotGrip(p)
    p.grip:SetPoint("LEFT", 2, 0)
    p.text = p:CreateFontString(nil, "OVERLAY")
    p.text:SetWordWrap(false)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", function(self)
        if ns.xpArrange and self.id and not drag then StartDrag({ kind = "piece", id = self.id, row = row }) end
    end)
    p:SetScript("OnDragStop", EndDrag)
    p:SetScript("OnEnter", function(self)
        local d = self.id and ns.xpPieces[self.id]
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(d.title)
        GameTooltip:AddLine("Drag along the row to move it, also to the other side of the bar's start.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p:Hide()
    row.pieces[n] = p
    return p
end

local function SetPiece(p, piece, side, h, arranging)
    local x = ns.db.xp
    ns.ApplyFont(p.text, x.font, x.size, x.outline)
    p.text:SetText(piece.text)
    local pad = arranging and 10 or 0
    p.text:ClearAllPoints()
    p.text:SetPoint("LEFT", pad, 0)
    p:SetSize(math.ceil(p.text:GetStringWidth() or 0) + pad + (arranging and 3 or 0), h)
    p.id, p.side = piece.id, side
    local draggable = arranging and piece.id ~= nil
    local c = ns.XP_SIDE_COLOUR[side]
    p.bg:SetColorTexture(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 0.8)   -- the side's colour, dark
    p.bg:SetShown(draggable)
    p.grip:SetShown(draggable)
    p:EnableMouse(draggable)
    p:SetAlpha((drag and drag.kind == "piece" and drag.id == piece.id and drag.row == p:GetParent()) and 0.4 or 1)
    p:ClearAllPoints()
    p:Show()
end

local function Row(i)
    local row = f.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, f)
    row.pieces = {}
    -- the bar starts right of the left pieces (gold, bags, durability, ...)
    row.bar = CreateFrame("Frame", nil, row)
    row.bar:SetPoint("TOPRIGHT"); row.bar:SetPoint("BOTTOMRIGHT")
    row.bar:SetPoint("LEFT", 0, 0)
    row.track = row.bar:CreateTexture(nil, "BACKGROUND")
    row.track:SetAllPoints()
    row.track:SetColorTexture(1, 1, 1, 0.04)
    row.fill = row.bar:CreateTexture(nil, "BORDER")
    row.fill:SetPoint("TOPLEFT"); row.fill:SetPoint("BOTTOMLEFT")
    row.rest = row.bar:CreateTexture(nil, "BORDER")
    row.rest:SetPoint("TOPLEFT", row.fill, "TOPRIGHT"); row.rest:SetPoint("BOTTOMLEFT", row.fill, "BOTTOMRIGHT")
    row.rest:SetColorTexture(0.65, 0.45, 1.0, 0.30)
    -- red, pulsing mark: this member stopped following
    row.alertLayer = CreateFrame("Frame", nil, row)   -- above the bar area
    row.alertLayer:SetAllPoints()
    row.alertLayer:SetFrameLevel(row:GetFrameLevel() + 3)
    row.alert = row.alertLayer:CreateTexture(nil, "OVERLAY")
    row.alert:SetAllPoints()
    row.alert:SetColorTexture(1, 0.1, 0.1, 0.35)
    row.alert.pulse = row.alert:CreateAnimationGroup()
    row.alert.pulse:SetLooping("BOUNCE")
    local afade = row.alert.pulse:CreateAnimation("Alpha")
    afade:SetFromAlpha(1); afade:SetToAlpha(0.3); afade:SetDuration(0.8)
    row.alert:Hide()
    -- orange, pulsing mark: this member can't move (stun, fear, root ...)
    row.ccMark = row.alertLayer:CreateTexture(nil, "OVERLAY")
    row.ccMark:SetAllPoints()
    row.ccMark:SetColorTexture(1, 0.55, 0.05, 0.35)
    row.ccMark.pulse = row.ccMark:CreateAnimationGroup()
    row.ccMark.pulse:SetLooping("BOUNCE")
    local cfade = row.ccMark.pulse:CreateAnimation("Alpha")
    cfade:SetFromAlpha(1); cfade:SetToAlpha(0.3); cfade:SetDuration(0.4)
    row.ccMark:Hide()
    row.name = row.bar:CreateFontString(nil, "OVERLAY")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    -- dots while arranging: the row itself can be dragged up or down
    row.grip = DotGrip(row.alertLayer)
    row.grip:SetPoint("RIGHT", row, "LEFT", -2, 0)
    row.grip:Hide()
    -- pulsing red "Layer Hop" left of the name; clickable even when the window is click-through
    row.hop = CreateFrame("Button", nil, row.bar)
    row.hop:SetPoint("LEFT", 2, 0)
    row.hop:SetFrameLevel(row:GetFrameLevel() + 5)
    row.hop.text = row.hop:CreateFontString(nil, "OVERLAY")
    row.hop.text:SetPoint("LEFT")
    row.hop.text:SetTextColor(1, 0.2, 0.2)
    local pulse = row.hop.text:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0.25); fade:SetDuration(0.6)
    row.hop.pulse = pulse
    row.hop:SetScript("OnClick", function() ns.HopClicked(row.key) end)
    row.hop:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Layer Hop", 1, 0.2, 0.2)
        if ns.IsSelf(row.key) then
            GameTooltip:AddLine("The game offers to move you to another layer. Click to accept in 3 seconds.", 1, 1, 1, true)
        else
            GameTooltip:AddLine(("%s has a layer hop pending. Click to make %s accept it in 3 seconds."):format(
                ns.FullDisplay(row.key), ns.FirstName(row.key)), 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    row.hop:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.hop:Hide()
    -- rows show details on mouseover and pass dragging / right-click to the window;
    -- while arranging, dragging a row (without Shift) moves it up or down
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(self)
        if ns.xpArrange and not IsShiftKeyDown() then
            if self.key and not drag then StartDrag({ kind = "row", key = self.key }) end
            return
        end
        f:GetScript("OnDragStart")(f)
    end)
    row:SetScript("OnDragStop", function()
        if drag then EndDrag() return end
        f:GetScript("OnDragStop")(f)
    end)
    row:SetScript("OnMouseUp", function(self, button) if self:IsMouseOver() then RowClick(self, button) end end)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rows[i] = row
    return row
end

local Hex = ns.XPHex

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return nil
end

-- names to show, in team order (your own character first if not in the team)
local function Members()
    local list = {}
    local me = ns.PlayerFull()
    local inTeam = false
    for _, key in ipairs(ns.SortedMembers()) do
        if ns.IsSelf(key) then
            inTeam = true
            if ns.db.xp.showSelf then list[#list + 1] = key end
        elseif (ns.IsOnline(key) and ns.status[key]) or ns.DebugMode() then
            list[#list + 1] = key   -- debug mode: offline members too
        end
    end
    if not inTeam and ns.db.xp.showSelf and me then table.insert(list, 1, me) end
    return list
end

-- a member's status; in debug mode members never heard from get an empty one
local function StatusOf(key)
    if ns.status[key] then return ns.status[key] end
    if ns.IsSelf(key) then return ns.UpdateOwnStatus() end
    local m = ns.db.team[key]
    return { level = 0, cur = 0, max = 0, rested = 0, class = m and m.class, noData = true }
end

-- the pieces right of the name; no data: only that, offline (debug mode): a note at the end
local function RightPieces(key, s, arranging)
    if s.noData and not arranging then return { { text = Hex(0.5, 0.5, 0.5) .. "offline, no data|r" } } end
    local list = ns.XPPiecesOf("RIGHT", key, s, arranging)
    if not ns.IsSelf(key) and not ns.IsOnline(key) then list[#list + 1] = { text = Hex(0.5, 0.5, 0.5) .. "offline|r" } end
    return list
end

-- lining up the pieces: a column per piece (in the pieces' order, notes like "offline" last),
-- as wide as its widest value; within it left / centred / right (x.pieceAlign)
local SHIFT = { LEFT = 0, CENTER = 0.5, RIGHT = 1 }

local function ColumnKey(p, n) return p.id or ("_" .. n) end

local function ByKey(frames)
    local t = {}
    for n, p in ipairs(frames) do t[ColumnKey(p, n)] = p end
    return t
end

-- { key, ... } in order, .width[key], .total (all columns and the gaps between them)
local function Columns(rowsFrames)
    local rank = {}
    for i, e in ipairs(ns.XPPieceOrder()) do rank[e.id] = i end
    local cols, width = {}, {}
    for _, frames in ipairs(rowsFrames) do
        for n, p in ipairs(frames) do
            local k = ColumnKey(p, n)
            if not width[k] then cols[#cols + 1] = k; width[k] = 0 end
            width[k] = math.max(width[k], p:GetWidth())
        end
    end
    table.sort(cols, function(a, b)
        local ra, rb = rank[a] or (1000 + #a), rank[b] or (1000 + #b)
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    local total = 0
    for i, k in ipairs(cols) do total = total + width[k] + (i > 1 and PieceGap() or 0) end
    cols.width, cols.total = width, total
    return cols
end

-- width of one row's pieces side by side
local function Flow(frames)
    local w = 0
    for n, p in ipairs(frames) do w = w + p:GetWidth() + (n > 1 and PieceGap() or 0) end
    return w
end

local function Update()
    local x = ns.db.xp
    if not x.enabled or not ns.ready then f:Hide() return end
    ns.UpdateOwnStatus()
    local list = Members()
    if #list == 0 then f:Hide() return end
    local arranging = ns.xpArrange and true or false
    local h = math.max(x.barHeight, x.size + 4)
    local gap = PieceGap()
    local lined = x.pieceAlign ~= "OFF"
    local shift = SHIFT[x.pieceAlign] or 0.5

    -- first pass: set up the pieces of every row (placed in the second pass)
    local lefts, rights = {}, {}
    for i, key in ipairs(list) do
        local s = StatusOf(key)
        local row = Row(i)
        lefts[i], rights[i] = {}, {}
        local pieces = (s.noData and not arranging) and {} or ns.XPPiecesOf("LEFT", key, s, arranging)
        for n, piece in ipairs(pieces) do
            local p = PieceFrame(row, n)
            SetPiece(p, piece, "LEFT", h, arranging)
            lefts[i][n] = p
        end
        for n, piece in ipairs(RightPieces(key, s, arranging)) do
            local p = PieceFrame(row, #pieces + n)
            SetPiece(p, piece, "RIGHT", h, arranging)
            rights[i][n] = p
        end
    end
    -- lined up: one column per piece, as wide as its widest value; else each row flows on its own
    local leftCols, rightCols = Columns(lefts), Columns(rights)
    local leftW, rightW = 0, 0
    for i = 1, #list do
        local lw = lined and leftCols.total or Flow(lefts[i])
        if lw > 0 then leftW = math.max(leftW, lw) end
        local rw = (lined and x.align == "SPLIT") and rightCols.total or Flow(rights[i])
        if rw > 0 then rightW = math.max(rightW, rw + gap) end
    end
    local barLeft = leftW > 0 and math.floor(leftW + 10) or 0
    -- wider than set when the pieces and some of the name don't fit (never overlapping)
    rowWidth = math.max(x.width, math.ceil(barLeft + 4 + NAME_ROOM + rightW + 4))
    local barWidth = math.max(20, rowWidth - barLeft)
    local rep = x.barMode == "REP"

    for i, key in ipairs(list) do
        local s = StatusOf(key)
        local row = Row(i)
        row.key, row.status = key, s
        row:EnableMouse(arranging or not x.clickThrough)
        row:SetAlpha((drag and drag.kind == "row" and drag.key == key) and 0.5 or 1)
        row.grip:SetShown(arranging)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD + (arranging and 10 or 0), -(PAD + (i - 1) * (h + Gap())))
        row:SetSize(rowWidth, h)
        local broken = x.followCheck and ns.FollowBroken and ns.FollowBroken(key)
        local ccText = ns.db.cc.enabled and ns.CCShort and ns.CCShort(key)
        local pulsing = broken and ns.FollowJustBroke(key) and not ccText
        row.alert:SetShown(pulsing and true or false)
        if pulsing then
            if not row.alert.pulse:IsPlaying() then row.alert.pulse:Play() end
        else
            row.alert.pulse:Stop()
        end
        row.ccMark:SetShown(ccText and true or false)
        if ccText then
            if not row.ccMark.pulse:IsPlaying() then row.ccMark.pulse:Play() end
        else
            row.ccMark.pulse:Stop()
        end
        -- after the name: "(no follow)", "(stunned 4)"
        local suffix = (broken and " |cffff4040(no follow)|r" or "") .. (ccText and (" |cffffa020(" .. ccText .. ")|r") or "")

        local cr, cg, cb = ClassColor(s.class)
        local useClass = x.classColors and cr
        local r, g, b = useClass and cr or A[1], useClass and cg or A[2], useClass and cb or A[3]

        -- left pieces (set up in the first pass), left to right
        if lined then
            local px, byKey = 4, ByKey(lefts[i])
            for _, k in ipairs(leftCols) do
                local p, cw = byKey[k], leftCols.width[k]
                if p then p:SetPoint("LEFT", row, "LEFT", px + math.floor((cw - p:GetWidth()) * shift), 0) end
                px = px + cw + gap
            end
        else
            local px = 4
            for _, p in ipairs(lefts[i]) do
                p:SetPoint("LEFT", row, "LEFT", px, 0)
                px = px + p:GetWidth() + gap
            end
        end
        row.bar:SetPoint("LEFT", barLeft, 0)

        local pct, restPct
        if rep then
            local rp = s.rep
            pct = (rp and (rp.max or 0) > 0) and math.min(1, math.max(0, rp.cur / rp.max)) or (rp and 1 or 0)
            restPct = 0
            local rr, rg, rb = ns.XPRepColour(rp and rp.standing or 4)
            row.fill:SetColorTexture(rr * 0.7, rg * 0.7, rb * 0.7, 0.85)
        else
            pct = (s.isMax or s.max <= 0) and 0 or math.min(1, s.cur / s.max)
            restPct = (s.isMax or s.max <= 0) and 0 or math.min(1 - pct, s.rested / s.max)
            row.fill:SetColorTexture(r * 0.6, g * 0.6, b * 0.6, 0.85)
        end
        row.fill:SetShown(x.showBars and pct > 0)
        row.fill:SetWidth(math.max(1, barWidth * pct))
        row.rest:SetShown(x.showBars and not rep and ns.XPPieceOn("rested") and restPct > 0)
        row.rest:SetWidth(math.max(1, barWidth * restPct))
        row.track:SetShown(x.showBars)

        local name = ns.Display(key)
        if ns.db.ftl.enabled and ns.db.ftl.crown and ns.IsFTLLeader(key) then
            local crown = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:0:0:0:-1|t"
            if ns.db.ftl.crownSide == "RIGHT" then name = name .. " " .. crown else name = crown .. name end
        end

        -- Layer Hop tag
        local hop = x.layerHopNotify and ns.HopPendingFor(key)
        local left = 4
        if hop then
            ns.ApplyFont(row.hop.text, x.font, x.size, x.outline)
            local cdLeft = ns.HopCountdownFor and ns.HopCountdownFor(key)
            row.hop.text:SetText(cdLeft and ("Layer Hop " .. cdLeft) or "Layer Hop")
            row.hop:SetSize(row.hop.text:GetStringWidth() + 4, h)
            row.hop:Show()
            if not row.hop.pulse:IsPlaying() then row.hop.pulse:Play() end
            left = row.hop:GetWidth() + 8
        else
            row.hop.pulse:Stop()
            row.hop:Hide()
        end

        -- the name, then the right pieces
        local nr, ng, nb = useClass and cr or 1, useClass and cg or 1, useClass and cb or 1
        ns.ApplyFont(row.name, x.font, x.size, x.outline)
        row.name:SetText(name .. suffix)
        row.name:SetTextColor(nr, ng, nb)
        row.name:ClearAllPoints()
        local frames = rights[i]
        if x.align == "SPLIT" and lined then
            -- name left, values right in their columns
            local rx, byKey = -4, ByKey(frames)
            for c = #rightCols, 1, -1 do
                local k = rightCols[c]
                local p, cw = byKey[k], rightCols.width[k]
                if p then p:SetPoint("RIGHT", row.bar, "RIGHT", rx - math.floor((cw - p:GetWidth()) * (1 - shift)), 0) end
                rx = rx - cw - gap
            end
            row.name:SetJustifyH("LEFT")
            row.name:SetPoint("LEFT", row.bar, "LEFT", left, 0)
            row.name:SetPoint("RIGHT", row.bar, "RIGHT", #rightCols > 0 and (rx + gap - 4) or -4, 0)
        elseif x.align == "SPLIT" then
            -- name left, values right (the name is cut short when it doesn't fit)
            local rx = -4
            for n = #frames, 1, -1 do
                frames[n]:SetPoint("RIGHT", row.bar, "RIGHT", rx, 0)
                rx = rx - frames[n]:GetWidth() - gap
            end
            row.name:SetJustifyH("LEFT")
            row.name:SetPoint("LEFT", row.bar, "LEFT", left, 0)
            row.name:SetPoint("RIGHT", frames[1] or row.bar, frames[1] and "LEFT" or "RIGHT", -4, 0)
        else
            -- name and values in one line, aligned left / centred / right
            local nameW = math.ceil(row.name:GetStringWidth() or 0)
            local total = nameW
            for _, p in ipairs(frames) do total = total + gap + p:GetWidth() end
            local start = left
            if x.align == "CENTER" then start = math.max(left, math.floor((barWidth - total) / 2))
            elseif x.align == "RIGHT" then start = math.max(left, barWidth - 4 - total) end
            row.name:SetJustifyH("LEFT")
            row.name:SetPoint("LEFT", row.bar, "LEFT", start, 0)
            row.name:SetWidth(nameW + 1)
            local cx = start + nameW + gap
            for _, p in ipairs(frames) do
                p:SetPoint("LEFT", row.bar, "LEFT", cx, 0)
                cx = cx + p:GetWidth() + gap
            end
        end
        for n = #lefts[i] + #frames + 1, #row.pieces do row.pieces[n]:Hide(); row.pieces[n].id = nil end
        row:Show()
    end
    for i = #list + 1, #f.rows do f.rows[i]:Hide() end

    f:SetScale(x.scale)
    f:SetAlpha(x.alpha)
    f:SetSize(rowWidth + PAD * 2 + (arranging and 10 or 0), #list * (h + Gap()) - Gap() + PAD * 2)
    f.bg:SetColorTexture(0, 0, 0, x.bgAlpha)
    f:Show()
end
ns.UpdateXPWindow = Update

local function Layout()
    local x = ns.db.xp
    f:ClearAllPoints()
    local p = x.point
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    f:EnableMouse(ns.xpArrange or not x.clickThrough)
    Update()
end

function ns.ResetXPPosition()
    ns.db.xp.point = { unpack(ns.defaults.xp.point) }
    Layout()
end

function ns.ToggleXPWindow()
    ns.db.xp.enabled = not ns.db.xp.enabled
    ns.Refresh()
end

ns.OnRefresh(Layout)
ns.Listen("STATUS_CHANGED", Update)
ns.Listen("TEAM_CHANGED", Update)
ns.Listen("PROFILE_CHANGED", function() if ns.ready then Layout() end end)
ns.OnLogin(function()
    C_Timer.NewTicker(5, Update) -- drops members whose heartbeat stopped, updates phase tags
end)
