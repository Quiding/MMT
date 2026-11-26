-- MMT: minimap button. Left-click opens or closes the settings (like /mmt),
-- right-click shows or hides the Info window, drag moves it around the minimap.
-- Shown or hidden with Profiles > "Show Minimap button"; per account
-- (MMTDB.minimap = { hide, angle }), like the settings window's scale.

local _, ns = ...
local UI = ns.UI

local button

local function Settings()
    MMTDB.minimap = MMTDB.minimap or {}
    return MMTDB.minimap
end

-- the button sits on the minimap's edge at its angle (degrees, 0 = right, counter-clockwise)
local function Place()
    if not button or not Minimap then return end
    local angle = math.rad(Settings().angle or 225)
    local w, h = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * w, math.sin(angle) * h)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    local atan2 = math.atan2 or math.atan
    Settings().angle = math.deg(atan2(py - my, px - mx)) % 360
    Place()
end

local function Create()
    if button or not Minimap then return button end
    local b = CreateFrame("Button", "MMTMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture(ns.ICON or "Interface\\AddOns\\MMT\\Media\\Icon")
    icon:SetPoint("TOPLEFT", 7, -6)
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            if ns.ToggleXPWindow then ns.ToggleXPWindow() end
        else
            ns.ToggleConfig()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("MMT - Manage My Team")
        GameTooltip:AddLine("Left-click: settings (/mmt)", 1, 1, 1)
        GameTooltip:AddLine("Right-click: show / hide the Info window", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button = b
    Place()
    return b
end

function ns.MinimapButtonShown()
    return not Settings().hide
end

function ns.SetMinimapButton(show)
    Settings().hide = (not show) or nil
    if show then
        Create()
        if button then button:Show() Place() end
    elseif button then
        button:Hide()
    end
end

ns.OnLogin(function()
    if ns.MinimapButtonShown() then ns.SetMinimapButton(true) end
end)

---------------------------------------------------------------------------
-- Game menu (Esc) buttons, shared by HUF and MMT (whichever loads first
-- sets it up, the newer code version runs it): the buttons sit in the
-- game menu under Shop, below EllesmereUI's buttons when it has them, as
-- wide and high as the menu's own buttons and in their look (EllesmereUI's
-- dark skin when the menu has it). The menu's later buttons move down by as
-- much and the menu grows by as much after every other change to it, so
-- EllesmereUI's own moving and sizing stay as they are.
---------------------------------------------------------------------------
local GAME_MENU_VERSION = 3
local function GameMenuRegistry()
    local menu = _G.GameMenuFrame
    if not menu then return nil end
    local reg = _G.HivemindGameMenu
    if type(reg) ~= "table" then
        reg = { entries = {} }
        _G.HivemindGameMenu = reg
        if menu.Layout then
            hooksecurefunc(menu, "Layout", function() if reg.Layout then pcall(reg.Layout) end end)
        end
    end
    if (reg.version or 0) < GAME_MENU_VERSION then
        reg.version = GAME_MENU_VERSION
        -- the look of the menu's own button `like` on button b
        reg.Style = function(b, like)
            local skinned = like and like.Left and like.Left:GetAlpha() == 0
            if not b.hmInset then
                local inset = CreateFrame("Frame", nil, b)
                inset:SetPoint("TOPLEFT", 2, -2)
                inset:SetPoint("BOTTOMRIGHT", -2, 2)
                inset:SetFrameLevel(b:GetFrameLevel())
                local bg = inset:CreateTexture(nil, "BACKGROUND", nil, -6)
                bg:SetAllPoints()
                bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
                    local t = inset:CreateTexture(nil, "BORDER")
                    t:SetColorTexture(0.32, 0.32, 0.32, 1)
                    if side == "TOP" or side == "BOTTOM" then
                        t:SetPoint(side .. "LEFT") t:SetPoint(side .. "RIGHT") t:SetHeight(1)
                    else
                        t:SetPoint("TOP" .. side) t:SetPoint("BOTTOM" .. side) t:SetWidth(1)
                    end
                end
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(inset)
                hl:SetColorTexture(1, 1, 1, 0.1)
                b.hmInset, b.hmHighlight = inset, hl
                -- every texture of the button's own art (pieces, normal / pushed /
                -- highlight / disabled), kept hidden while the menu is skinned
                local art, seen = {}, {}
                local function Take(t)
                    if t and t ~= hl and not seen[t] and t.IsObjectType and t:IsObjectType("Texture") then
                        seen[t] = true
                        art[#art + 1] = t
                        hooksecurefunc(t, "SetAlpha", function(s, a) if b.hmSkinned and a > 0 then s:SetAlpha(0) end end)
                    end
                end
                for _, r in ipairs({ b:GetRegions() }) do Take(r) end
                Take(b:GetNormalTexture()) Take(b:GetPushedTexture())
                Take(b:GetHighlightTexture()) Take(b:GetDisabledTexture())
                b.hmArt = art
            end
            b.hmSkinned = skinned and true or false
            for _, t in ipairs(b.hmArt) do t:SetAlpha(skinned and 0 or 1) end
            local label = b:GetFontString()
            if label then
                label:ClearAllPoints()
                label:SetPoint("CENTER", 0, 0)
            end
            b.hmInset:SetShown(b.hmSkinned)
            b.hmHighlight:SetShown(b.hmSkinned)
            -- the same font and text colour as the menu's button
            local fs, lfs = b:GetFontString(), like and like:GetFontString()
            if fs and lfs then
                local font, size, flags = lfs:GetFont()
                if font then fs:SetFont(font, size or 13, flags or "") end
                local r, g, bl = lfs:GetTextColor()
                if r then fs:SetTextColor(r, g, bl, 1) end
            end
        end
        reg.Layout = function()
            local entries = reg.entries
            if InCombatLockdown() then
                for _, e in ipairs(entries) do e.button:Hide() end
                return
            end
            -- under Shop (else Options), like EllesmereUI's buttons
            local anchor
            if menu.buttonPool and menu.buttonPool.EnumerateActive then
                for b in menu.buttonPool:EnumerateActive() do
                    local t = b:GetText()
                    if t == BLIZZARD_STORE then anchor = b break
                    elseif t == GAMEMENU_OPTIONS then anchor = b end
                end
            end
            if not anchor then
                for _, e in ipairs(entries) do e.button:Hide() end
                return
            end
            -- below EllesmereUI's buttons when they show
            local last, gap = anchor, -12
            for _, name in ipairs({ "EllesmereUI_GameMenuButton", "EllesmereUI_UnlockMenuButton" }) do
                local eb = _G[name]
                if eb and eb:GetParent() == menu and eb:IsShown() then last, gap = eb, -4 end
            end
            table.sort(entries, function(a, b) return a.order < b.order end)
            local w, h = anchor:GetWidth(), anchor:GetHeight()
            if not (w and w > 0) then w, h = 200, 35 end
            local extra = 0
            for _, e in ipairs(entries) do
                local ok, on = true, true
                if e.shown then ok, on = pcall(e.shown) end
                on = ok and on and true or false
                local b = e.button
                b:SetShown(on)
                if on then
                    b:SetSize(w, h)
                    b:ClearAllPoints()
                    b:SetPoint("TOP", last, "BOTTOM", 0, gap)
                    pcall(reg.Style, b, anchor)
                    extra = extra + h - gap
                    last, gap = b, -4
                end
            end
            if extra <= 0 then return end
            -- the menu's own buttons after the anchor move down (by their layout order)
            local idx = anchor.layoutIndex
            if idx then
                for b in menu.buttonPool:EnumerateActive() do
                    if b.layoutIndex and b.layoutIndex > idx then
                        local p, rel, rp, x, y = b:GetPoint(1)
                        if p then
                            b:ClearAllPoints()
                            b:SetPoint(p, rel, rp, x, (y or 0) - extra)
                        end
                    end
                end
            end
            -- the height: once, after every other hook of this layout (EllesmereUI sets its own)
            reg.extra, reg.added = extra, false
            if not reg.pending then
                reg.pending = true
                C_Timer.After(0, function()
                    reg.pending = false
                    if not reg.added and (reg.extra or 0) > 0 then
                        menu:SetHeight(menu:GetHeight() + reg.extra)
                        reg.added = true
                    end
                end)
            end
        end
    end
    return reg
end
-- order: place among the buttons (HUF 1, MMT 2); shown(): the addon's option
local function AddGameMenuButton(order, text, onClick, shown)
    local reg = GameMenuRegistry()
    if not reg then return nil end
    local menu = _G.GameMenuFrame
    local ok, b = pcall(CreateFrame, "Button", nil, menu, "MainMenuFrameButtonTemplate")
    if not ok or not b then b = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate") end
    b:SetText(text)
    b:Hide()
    b:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        HideUIPanel(menu)
        onClick()
    end)
    reg.entries[#reg.entries + 1] = { order = order, button = b, shown = shown }
    return b
end
-- after an option change while the menu is open
local function RelayoutGameMenu()
    local menu = _G.GameMenuFrame
    if menu and menu:IsShown() and menu.Layout then pcall(menu.Layout, menu) end
end

-- MMT's button (Profiles: "Button in the game menu (Esc)", account-wide like the minimap button)
function ns.GameMenuButtonShown() return not (MMTDB and MMTDB.gameMenuButton == false) end
function ns.SetGameMenuButton(on)
    if MMTDB then MMTDB.gameMenuButton = on and true or false end
    RelayoutGameMenu()
end
ns.OnLogin(function()
    AddGameMenuButton(2, "MMT", function() ns.ToggleConfig() end, ns.GameMenuButtonShown)
end)
