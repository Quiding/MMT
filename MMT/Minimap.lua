-- MMT: minimap button. Left-click opens or closes the settings (like /mmt),
-- right-click shows or hides the XP window, drag moves it around the minimap.
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
        GameTooltip:AddLine("Right-click: show / hide the XP window", 1, 1, 1)
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
