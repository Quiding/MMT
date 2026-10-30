-- MMT: backgrounds for the settings window (/mmt > Appearance).
-- Built only from colour textures and gradients (no art files), drawn on the
-- window's BACKGROUND layer between its fill and its border, so the nav list,
-- pages and text stay on top. The choice is per account (MMTDB.configBackground),
-- like the window scale: the same screen for every character and profile.

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT

-- value, name, line for the Appearance page; order = order in the dropdown
ns.BACKGROUNDS = {
    { value = "NONE",     text = "None",        desc = "The plain MMT window." },
    { value = "DARK",     text = "Dark",        desc = "Nearly black and nearly opaque: the most contrast, nothing of the game shows through." },
    { value = "DUSK",     text = "Dusk",        desc = "A soft gradient from a cool slate grey at the top to black at the bottom." },
    { value = "VIGNETTE", text = "Vignette",    desc = "Edges and corners fade to black, the middle stays lighter." },
    { value = "ACCENT",   text = "Accent glow", desc = "A glow of MMT's accent colour from the top edge, with a thin accent line." },
    { value = "CLASS",    text = "Class glow",  desc = "A glow in this character's class colour, rising from the bottom left." },
    { value = "GRID",     text = "Grid",        desc = "A faint grid of accent-tinted lines that fades out towards the bottom." },
    { value = "GLASS",    text = "Glass",       desc = "Lighter and see-through, with a sheen across the top like frosted glass." },
}

local BASE = { 0.05, 0.05, 0.06, 0.94 }   -- the window's own fill (Config.lua)
-- fill colour per background; nil = BASE
local FILL = {
    DARK     = { 0.025, 0.025, 0.03, 0.985 },
    DUSK     = { 0.04, 0.04, 0.05, 0.95 },
    VIGNETTE = { 0.07, 0.07, 0.08, 0.94 },
    GRID     = { 0.045, 0.05, 0.06, 0.95 },
    GLASS    = { 0.10, 0.11, 0.13, 0.80 },
}

function ns.ConfigBackground()
    local v = MMTDB and MMTDB.configBackground
    for _, b in ipairs(ns.BACKGROUNDS) do
        if b.value == v then return v end
    end
    return "NONE"
end

-- gradient from (r1, g1, b1, a1) to (r2, g2, b2, a2): VERTICAL goes bottom -> top,
-- HORIZONTAL left -> right
local function Gradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    tex:SetColorTexture(1, 1, 1, 1)
    if CreateColor and tex.SetGradient then
        tex:SetGradient(orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    elseif tex.SetGradientAlpha then
        tex:SetGradientAlpha(orient, r1, g1, b1, a1, r2, g2, b2, a2)
    end
end

local function ClassColor()
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return A[1], A[2], A[3]
end

-- Each builder makes its textures with tex(sublevel) and may return a function that
-- recolours them (run on every apply: class or accent colour can differ).
local BUILD = {}

BUILD.DUSK = function(tex)
    local t = tex(1)
    t:SetAllPoints()
    Gradient(t, "VERTICAL", 0, 0, 0, 0.45, 0.20, 0.23, 0.30, 0.22)
end

BUILD.VIGNETTE = function(tex, w, h)
    local function band(p1, p2, size, orient, darkFirst)
        local t = tex(1)
        t:SetPoint(p1); t:SetPoint(p2)
        if orient == "VERTICAL" then t:SetHeight(size) else t:SetWidth(size) end
        -- darkFirst: dark at the bottom / left end of the band, else at the top / right
        if darkFirst then Gradient(t, orient, 0, 0, 0, 0.6, 0, 0, 0, 0)
        else Gradient(t, orient, 0, 0, 0, 0, 0, 0, 0, 0.6) end
    end
    band("TOPLEFT", "TOPRIGHT", h * 0.28, "VERTICAL", false)          -- dark at the top edge
    band("BOTTOMLEFT", "BOTTOMRIGHT", h * 0.28, "VERTICAL", true)     -- dark at the bottom edge
    band("TOPLEFT", "BOTTOMLEFT", w * 0.22, "HORIZONTAL", true)       -- dark at the left edge
    band("TOPRIGHT", "BOTTOMRIGHT", w * 0.22, "HORIZONTAL", false)    -- dark at the right edge
end

BUILD.ACCENT = function(tex, w, h)
    local glow = tex(1)
    glow:SetPoint("TOPLEFT"); glow:SetPoint("TOPRIGHT")
    glow:SetHeight(h * 0.4)
    local side = tex(1)
    side:SetPoint("TOPRIGHT"); side:SetPoint("BOTTOMRIGHT")
    side:SetWidth(w * 0.35)
    local line = tex(2)
    line:SetPoint("TOPLEFT", 1, -1); line:SetPoint("TOPRIGHT", -1, -1)
    line:SetHeight(2)
    return function()
        local r, g, b = A[1], A[2], A[3]
        Gradient(glow, "VERTICAL", r, g, b, 0, r, g, b, 0.16)
        Gradient(side, "HORIZONTAL", r, g, b, 0, r, g, b, 0.06)
        Gradient(line, "HORIZONTAL", r, g, b, 0.15, r, g, b, 0.7)
    end
end

BUILD.CLASS = function(tex, w, h)
    local left = tex(1)
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
    left:SetWidth(w * 0.4)
    local bottom = tex(1)
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(h * 0.35)
    local line = tex(2)
    line:SetPoint("BOTTOMLEFT", 1, 1); line:SetPoint("BOTTOMRIGHT", -1, 1)
    line:SetHeight(2)
    return function()
        local r, g, b = ClassColor()
        Gradient(left, "HORIZONTAL", r, g, b, 0.12, r, g, b, 0)
        Gradient(bottom, "VERTICAL", r, g, b, 0.12, r, g, b, 0)
        Gradient(line, "HORIZONTAL", r, g, b, 0.7, r, g, b, 0.1)
    end
end

BUILD.GRID = function(tex, w, h)
    local STEP = 24
    local lines = {}
    for x = STEP, w - 1, STEP do
        local t = tex(1)
        t:SetPoint("TOPLEFT", x, -1); t:SetPoint("BOTTOMLEFT", x, 1)
        t:SetWidth(1)
        lines[#lines + 1] = t
    end
    for y = STEP, h - 1, STEP do
        local t = tex(1)
        t:SetPoint("TOPLEFT", 1, -y); t:SetPoint("TOPRIGHT", -1, -y)
        t:SetHeight(1)
        lines[#lines + 1] = t
    end
    -- the fill's colour over the lines' lower part: the grid fades out
    local fade = tex(2)
    fade:SetPoint("BOTTOMLEFT"); fade:SetPoint("BOTTOMRIGHT")
    fade:SetHeight(h * 0.7)
    local f = FILL.GRID
    Gradient(fade, "VERTICAL", f[1], f[2], f[3], 0.95, f[1], f[2], f[3], 0)
    return function()
        for _, t in ipairs(lines) do t:SetColorTexture(A[1], A[2], A[3], 0.07) end
    end
end

BUILD.GLASS = function(tex, w, h)
    local sheen = tex(1)
    sheen:SetPoint("TOPLEFT"); sheen:SetPoint("TOPRIGHT")
    sheen:SetHeight(h * 0.45)
    Gradient(sheen, "VERTICAL", 1, 1, 1, 0, 1, 1, 1, 0.07)
    local diagonal = tex(1)   -- a brighter strip across the upper left
    diagonal:SetPoint("TOPLEFT"); diagonal:SetPoint("BOTTOMLEFT")
    diagonal:SetWidth(w * 0.5)
    Gradient(diagonal, "HORIZONTAL", 1, 1, 1, 0.035, 1, 1, 1, 0)
    local shade = tex(1)      -- darker at the bottom: the footer text stays readable
    shade:SetPoint("BOTTOMLEFT"); shade:SetPoint("BOTTOMRIGHT")
    shade:SetHeight(h * 0.25)
    Gradient(shade, "VERTICAL", 0, 0, 0, 0.35, 0, 0, 0, 0)
    local edge = tex(2)       -- light catching the top edge
    edge:SetPoint("TOPLEFT", 1, -1); edge:SetPoint("TOPRIGHT", -1, -1)
    edge:SetHeight(1)
    edge:SetColorTexture(1, 1, 1, 0.14)
end

-- frame: the settings window; frame.baseFill = its fill texture (UI.Fill)
function ns.ApplyBackground(frame, key)
    if not frame then return end
    key = key or ns.ConfigBackground()
    frame.bgSets = frame.bgSets or {}
    for k, set in pairs(frame.bgSets) do
        if k ~= key then
            for _, t in ipairs(set.textures) do t:Hide() end
        end
    end
    local c = FILL[key] or BASE
    if frame.baseFill then frame.baseFill:SetColorTexture(c[1], c[2], c[3], c[4]) end
    if not BUILD[key] then return end
    local set = frame.bgSets[key]
    if not set then
        set = { textures = {} }
        local function tex(sub)
            local t = frame:CreateTexture(nil, "BACKGROUND", nil, sub)
            set.textures[#set.textures + 1] = t
            return t
        end
        set.color = BUILD[key](tex, frame:GetWidth(), frame:GetHeight())
        frame.bgSets[key] = set
    end
    if set.color then set.color() end
    for _, t in ipairs(set.textures) do t:Show() end
end

function ns.SetConfigBackground(key)
    MMTDB.configBackground = (key ~= "NONE") and key or nil
    if ns.configWindow then ns.ApplyBackground(ns.configWindow) end
end
