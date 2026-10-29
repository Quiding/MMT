-- MMT Statistics: a small line chart (gold over the last 60 days).
--   chart = mod.CreateChart(parent, width, height)
--   chart:SetData({ {label, value|nil}, ... }, format)   value nil = no data
-- Lines are drawn with Frame:CreateLine; hovering shows the day's value.

local _, mod = ...
local MMT = MMT
local UI = MMT.UI
local A = UI.ACCENT

local PAD_L, PAD_R, PAD_T, PAD_B = 70, 10, 10, 18

function mod.CreateChart(parent, width, height)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width, height)
    UI.Fill(c, 1, 1, 1, 0.025)
    UI.Border(c, 1, 1, 1, 0.08)
    c.plotW, c.plotH = width - PAD_L - PAD_R, height - PAD_T - PAD_B

    -- grid lines and axis labels: top, middle, bottom
    c.grid, c.yLabels = {}, {}
    for i = 1, 3 do
        local g = c:CreateTexture(nil, "BORDER")
        g:SetColorTexture(1, 1, 1, 0.06)
        g:SetHeight(1)
        g:SetPoint("LEFT", c, "BOTTOMLEFT", PAD_L, PAD_B + c.plotH * (i - 1) / 2)
        g:SetWidth(c.plotW)
        c.grid[i] = g
        local l = UI.Label(c, "")
        l:SetPoint("RIGHT", c, "BOTTOMLEFT", PAD_L - 6, PAD_B + c.plotH * (i - 1) / 2)
        l:SetTextColor(0.6, 0.6, 0.6)
        c.yLabels[i] = l
    end
    c.xFirst = UI.Label(c, "")
    c.xFirst:SetPoint("BOTTOMLEFT", PAD_L, 3)
    c.xFirst:SetTextColor(0.6, 0.6, 0.6)
    c.xLast = UI.Label(c, "")
    c.xLast:SetPoint("BOTTOMRIGHT", -PAD_R, 3)
    c.xLast:SetTextColor(0.6, 0.6, 0.6)
    c.empty = UI.Label(c, "No gold recorded yet.")
    c.empty:SetPoint("CENTER")
    c.empty:SetTextColor(0.5, 0.5, 0.5)

    c.lines = {}
    local function Line(i)
        local l = c.lines[i]
        if not l then
            local ok, line = pcall(function() return c.CreateLine and c:CreateLine(nil, "ARTWORK") end)
            if ok and line and line.SetStartPoint then
                l = line
                l:SetThickness(2)
            else   -- no lines on this client: small dots instead
                l = c:CreateTexture(nil, "ARTWORK")
                l:SetSize(3, 3)
            end
            l:SetColorTexture(A[1], A[2], A[3], 1)
            c.lines[i] = l
        end
        return l
    end

    -- hover marker
    c.marker = c:CreateTexture(nil, "OVERLAY")
    c.marker:SetColorTexture(1, 1, 1, 0.25)
    c.marker:SetWidth(1)
    c.marker:SetHeight(c.plotH)
    c.marker:Hide()
    c.dot = c:CreateTexture(nil, "OVERLAY")
    c.dot:SetColorTexture(1, 1, 1, 1)
    c.dot:SetSize(5, 5)
    c.dot:Hide()

    local function XY(i, v)
        local n = #c.points
        local x = PAD_L + (n > 1 and (i - 1) / (n - 1) or 0.5) * c.plotW
        local y = PAD_B + (c.max > c.min and (v - c.min) / (c.max - c.min) or 0.5) * c.plotH
        return x, y
    end

    function c:SetData(points, format)
        self.points, self.format = points, format
        local lo, hi
        for _, p in ipairs(points) do
            local v = p[2]
            if v then lo = math.min(lo or v, v); hi = math.max(hi or v, v) end
        end
        for _, l in ipairs(self.lines) do l:Hide() end
        self.empty:SetShown(lo == nil)
        if not lo then
            for _, l in ipairs(self.yLabels) do l:SetText("") end
            self.xFirst:SetText(""); self.xLast:SetText("")
            return
        end
        -- a little room above and below; a flat line sits in the middle
        local pad = (hi - lo) * 0.05
        if pad == 0 then pad = math.max(10000, hi * 0.05) end
        self.min, self.max = math.max(0, lo - pad), hi + pad
        for i, l in ipairs(self.yLabels) do
            l:SetText(format(self.min + (self.max - self.min) * (i - 1) / 2))
        end
        local first
        for i, p in ipairs(points) do if p[2] then first = first or i end end
        self.xFirst:SetText(points[first][1]:sub(6))
        self.xLast:SetText(points[#points][1]:sub(6))
        -- one line per pair of neighbouring days with data
        local k, prev = 0, nil
        for i, p in ipairs(points) do
            if p[2] then
                local x, y = XY(i, p[2])
                k = k + 1
                local l = Line(k)
                if l.SetStartPoint and prev then
                    l:SetStartPoint("BOTTOMLEFT", self, prev[1], prev[2])
                    l:SetEndPoint("BOTTOMLEFT", self, x, y)
                    l:Show()
                elseif not l.SetStartPoint then
                    l:ClearAllPoints()
                    l:SetPoint("CENTER", self, "BOTTOMLEFT", x, y)
                    l:Show()
                end
                prev = { x, y }
            end
        end
    end

    -- hover: the nearest day with its value
    c:EnableMouse(true)
    c:SetScript("OnUpdate", function(self)
        if not self:IsMouseOver() or not self.points or not self.min then
            if self.marker:IsShown() then self.marker:Hide(); self.dot:Hide(); GameTooltip:Hide() end
            return
        end
        local scale = self:GetEffectiveScale()
        local mx = GetCursorPosition() / scale - self:GetLeft()
        local n = #self.points
        local i = math.floor((mx - PAD_L) / math.max(1, self.plotW) * (n - 1) + 1.5)
        i = math.max(1, math.min(n, i))
        if i == self.hover and self.marker:IsShown() then return end
        self.hover = i
        local p = self.points[i]
        local x = XY(i, 0)
        self.marker:ClearAllPoints()
        self.marker:SetPoint("BOTTOM", self, "BOTTOMLEFT", x, PAD_B)
        self.marker:Show()
        if p[2] then
            local _, y = XY(i, p[2])
            self.dot:ClearAllPoints()
            self.dot:SetPoint("CENTER", self, "BOTTOMLEFT", x, y)
            self.dot:Show()
        else
            self.dot:Hide()
        end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(p[1])
        GameTooltip:AddLine(p[2] and self.format(p[2]) or "no data", 1, 1, 1)
        GameTooltip:Show()
    end)
    return c
end
