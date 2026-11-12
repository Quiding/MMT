-- MMT: search box in the settings window (top right): finds a setting on any page - MMT's
-- own and every module's - by its name or its tooltip, and jumps to it.
--
-- The first time the box gets the focus every page is built (hidden; pages are otherwise built
-- when first opened), then all of them are read: each text on a page (checkbox and slider
-- names, buttons, tile titles, notes) and each tooltip (UI.Tooltip keeps them on the frame),
-- with the sub-tab it sits on - a tab panel says which tab shows it (frame.mmtTab = { label,
-- show }: ConfigHelpers.TabStrip, and the modules' own tab strips can do the same). Read again
-- each time the box gets the focus: lists and texts change.
--
-- A result: its page opens, its sub-tabs are chosen, a scroll frame around it scrolls to it,
-- and it flashes. Enter takes the first result; Esc clears.

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT

local RES_W = 420
local index = {}            -- { text, low, tip, lowTip, frame, page, path, order }
local built = false
local results, box, list
local found = {}

local function Clean(s)
    if type(s) ~= "string" or (ns.IsSecret and ns.IsSecret(s)) then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h", ""):gsub("|h", "")
    s = s:gsub("%s+", " "):match("^%s*(.-)%s*$")
    return s
end

-- a text worth finding: some letters, not a value ("50%", "1.00", "x", "+")
local function Useful(s)
    return s and #s >= 3 and s:find("%a%a") ~= nil
end

local function PageOrder()
    local order = {}
    for _, key in ipairs(ns.ConfigCoreOrder or {}) do order[#order + 1] = key end
    local mods = {}
    for key, page in pairs(ns.configPages or {}) do
        if page.module then mods[#mods + 1] = page end
    end
    table.sort(mods, function(a, b) return (a.title or "") < (b.title or "") end)
    for _, page in ipairs(mods) do order[#order + 1] = page.key end
    if ns.configPages and ns.configPages.modules then order[#order + 1] = "modules" end
    return order
end

-- frames from the widget up to its page: hidden by something else than a tab panel = not findable now
local function Reachable(f, pageFrame)
    local x = f
    while x and x ~= pageFrame do
        if x.IsShown and not x:IsShown() and not x.mmtTab then return false end
        x = x.GetParent and x:GetParent()
    end
    return x == pageFrame
end

local function Walk(f, page, ctx, out, seen, depth)
    if depth > 30 or f == results or f.mmtNoSearch then return end
    if f.mmtTab then
        local tabs = {}
        for i, t in ipairs(ctx.tabs) do tabs[i] = t end
        tabs[#tabs + 1] = f.mmtTab
        ctx = { tabs = tabs, tile = ctx.tile }
    end
    if f.title and type(f.title) == "table" and f.title.GetText and f ~= page.frame then
        local t = Clean(f.title:GetText())
        if t then ctx = { tabs = ctx.tabs, tile = t } end
    end
    local function Add(text, tip, owner)
        local key = tostring(owner) .. "\001" .. (text or "") .. "\001" .. (tip or "")
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = { text = text, tip = tip, frame = owner, page = page, tabs = ctx.tabs, tile = ctx.tile }
    end
    local isEdit = f.GetObjectType and f:GetObjectType() == "EditBox"
    local label
    if not isEdit then
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and r:IsShown() then
                local t = Clean(r:GetText())
                if Useful(t) then
                    label = label or t
                    Add(t, nil, f)
                end
            end
        end
    end
    local tipTitle, tip = Clean(f.mmtTipTitle), Clean(f.mmtTip)
    if tipTitle or tip then
        Add(label or tipTitle or tip, ((tipTitle and tipTitle ~= label) and (tipTitle .. " - ") or "") .. (tip or ""), f)
    end
    for _, c in ipairs({ f:GetChildren() }) do Walk(c, page, ctx, out, seen, depth + 1) end
end

local function BuildIndex()
    wipe(index)
    local pages = ns.configPages or {}
    for n, key in ipairs(PageOrder()) do
        local page = pages[key]
        if page and not page.frame and ns.ConfigBuildPage then
            local ok, err = pcall(ns.ConfigBuildPage, page)
            if not ok then ns.Debug("search: page %s failed to build: %s", tostring(key), tostring(err)) end
        end
        if page and page.frame then
            local out, seen = {}, {}
            Walk(page.frame, page, { tabs = {} }, out, seen, 0)
            for _, e in ipairs(out) do
                if Reachable(e.frame, page.frame) then
                    e.low = e.text and e.text:lower() or ""
                    e.lowTip = e.tip and e.tip:lower() or nil
                    e.order = n
                    local parts = { page.title }
                    for _, t in ipairs(e.tabs) do parts[#parts + 1] = t.label end
                    if e.tile and e.tile ~= e.text then parts[#parts + 1] = e.tile end
                    e.path = table.concat(parts, " > ") .. ((page.module and not page.module.enabled) and "  (off)" or "")
                    index[#index + 1] = e
                end
            end
        end
    end
    built = true
end
ns.SearchIndex = function() if not built then BuildIndex() end return index end
ns.SearchRebuild = BuildIndex

local function Esc(w) return (w:gsub("%p", "%%%0")) end

-- does a word of text start with w? (so "mount" finds "Mount up", not "amount")
local function WordStart(low, w)
    return low and low:find("%f[%w]" .. Esc(w)) ~= nil
end

-- how well e matches the words: 0 = not at all. Every word must start a word of the
-- setting's name or of its tooltip
local function Score(e, words, query)
    local allText = true
    for _, w in ipairs(words) do
        local inText = WordStart(e.low, w)
        if not inText then
            allText = false
            if not WordStart(e.lowTip, w) then return 0 end
        end
    end
    local s
    if e.low == query then s = 100
    elseif e.low:sub(1, #query) == query then s = 80
    elseif allText and WordStart(e.low, query) then s = 60
    elseif allText then s = 40
    else s = 5 end   -- (partly) only in the tooltip
    if #e.text > 90 then s = s - 20 end   -- a long note: after the settings themselves
    return s
end

local function Words(query)
    local words = {}
    for w in query:gmatch("%S+") do words[#words + 1] = w end
    return words
end

function ns.SearchSettings(query)
    query = (query or ""):lower():gsub("%s+", " "):match("^%s*(.-)%s*$")
    if #query < 2 then return {} end
    local words = Words(query)
    local out, seenText = {}, {}
    for _, e in ipairs(ns.SearchIndex()) do
        local s = Score(e, words, query)
        if s > 0 then
            -- the same text on the same page and tab once (a label and its tooltip)
            local k = e.path .. "\001" .. e.low
            local had = seenText[k]
            if not had then
                e.score = s
                seenText[k] = e
                out[#out + 1] = e
            elseif s > had.score then
                had.score = s
            end
        end
    end
    -- grouped by where they are (the best group first), the best match first in each
    local best = {}
    for _, e in ipairs(out) do best[e.path] = math.max(best[e.path] or 0, e.score) end
    table.sort(out, function(a, b)
        if a.path ~= b.path then
            if best[a.path] ~= best[b.path] then return best[a.path] > best[b.path] end
            if a.order ~= b.order then return a.order < b.order end
            return a.path < b.path
        end
        if a.score ~= b.score then return a.score > b.score end
        return #a.text < #b.text
    end)
    ns.searchWords = words
    return out
end

-- text with the query's words in the accent colour (case kept)
local HL = ("|cff%02x%02x%02x"):format(A[1] * 255, A[2] * 255, A[3] * 255)
local function Highlight(text, words)
    local low = text:lower()
    local marks = {}
    for _, w in ipairs(words or {}) do
        local i = low:find("%f[%w]" .. Esc(w))
        if i then marks[#marks + 1] = { i, i + #w - 1 } end
    end
    table.sort(marks, function(x, y) return x[1] > y[1] end)
    for _, m in ipairs(marks) do
        text = text:sub(1, m[1] - 1) .. HL .. text:sub(m[1], m[2]) .. "|r" .. text:sub(m[2] + 1)
    end
    return text
end
ns.SearchHighlight = Highlight

-- a short piece of the tooltip around the first word found there
local function Snippet(tip, words)
    if not tip then return nil end
    local low = tip:lower()
    for _, w in ipairs(words or {}) do
        local i = low:find("%f[%w]" .. Esc(w))
        if i then
            local from = math.max(1, i - 30)
            local piece = tip:sub(from, from + 80)
            return (from > 1 and "..." or "") .. piece .. (from + 80 < #tip and "..." or "")
        end
    end
end

---------------------------------------------------------------------------
-- Going to a result
---------------------------------------------------------------------------
local flash
local function Flash(f)
    if not (f and f.GetCenter and f:IsVisible()) then return end
    if not flash then
        flash = CreateFrame("Frame", nil, UIParent)
        flash:SetFrameStrata("TOOLTIP")
        local function Edge(p1, p2, w, h)
            local t = flash:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(A[1], A[2], A[3], 1)
            t:SetPoint(p1); t:SetPoint(p2)
            if w then t:SetWidth(w) end
            if h then t:SetHeight(h) end
        end
        Edge("TOPLEFT", "TOPRIGHT", nil, 2); Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
        Edge("TOPLEFT", "BOTTOMLEFT", 2, nil); Edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
        local fill = flash:CreateTexture(nil, "ARTWORK")
        fill:SetAllPoints()
        fill:SetColorTexture(A[1], A[2], A[3], 0.12)
    end
    flash:SetParent(f)
    flash:SetFrameStrata("TOOLTIP")
    flash:ClearAllPoints()
    flash:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
    flash:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
    flash.t = 0
    flash:Show()
    flash:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        if self.t > 2.4 then self:Hide() self:SetScript("OnUpdate", nil) return end
        self:SetAlpha(0.35 + 0.65 * math.abs(math.cos(self.t * 3.9)))
    end)
end

-- a scroll frame around f: scrolled so f is in view
local function ScrollTo(f)
    local x = f and f:GetParent()
    while x do
        if x.GetObjectType and x:GetObjectType() == "ScrollFrame" and x.GetScrollChild and x:GetScrollChild() then
            local child = x:GetScrollChild()
            local top, ftop = child:GetTop(), f:GetTop()
            if top and ftop then
                local want = top - ftop - 20
                local max = x:GetVerticalScrollRange() or 0
                x:SetVerticalScroll(math.max(0, math.min(max, want)))
            end
            return
        end
        x = x:GetParent()
    end
end

local function Go(e)
    if not e then return end
    if results then results:Hide() end
    if box then box:ClearFocus() end
    if ns.ConfigSelect then ns.ConfigSelect(e.page.key) end
    for _, t in ipairs(e.tabs or {}) do pcall(t.show) end
    C_Timer.After(0, function()
        ScrollTo(e.frame)
        C_Timer.After(0, function() Flash(e.frame) end)
    end)
end
ns.SearchGo = Go

---------------------------------------------------------------------------
-- The box and its list: results under a line per place (page > tab > tile), the
-- matching words in the accent colour; a match only in the tooltip shows that piece of it
---------------------------------------------------------------------------
local RES_H = 430          -- most the list is tall
local HEAD_H, ITEM_H, SNIP_H = 20, 20, 14
local lines = {}           -- what the list shows: { head = path } / { entry = e }
local first = 1            -- first line shown
local pool = {}

local function Row(i)
    local r = pool[i]
    if r then return r end
    r = CreateFrame("Button", nil, results.view)
    r:SetPoint("LEFT", 0, 0); r:SetPoint("RIGHT", 0, 0)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.06)
    r.line = r:CreateTexture(nil, "ARTWORK")
    r.line:SetColorTexture(A[1], A[2], A[3], 0.25)
    r.line:SetHeight(1)
    r.line:SetPoint("BOTTOMLEFT", 8, 0); r.line:SetPoint("BOTTOMRIGHT", -8, 0)
    r.text = UI.Label(r, "", "GameFontHighlight")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.snip = UI.Label(r, "", "GameFontHighlightSmall")
    r.snip:SetJustifyH("LEFT")
    r.snip:SetWordWrap(false)
    r.snip:SetTextColor(0.55, 0.55, 0.55)
    r:SetScript("OnClick", function(self) if self.entry then Go(self.entry) end end)
    pool[i] = r
    return r
end

local function Render()
    if not results then return end
    local words = ns.searchWords
    -- the lines: a head before each new place
    wipe(lines)
    local place
    for _, e in ipairs(found) do
        if e.path ~= place then
            place = e.path
            lines[#lines + 1] = { head = place }
        end
        lines[#lines + 1] = { entry = e }
    end
    first = math.max(1, math.min(first, #lines))
    local y, used, n = -6, 0, 0
    for i = first, #lines do
        local l = lines[i]
        local snip = l.entry and l.entry.score <= 5 and Snippet(l.entry.tip, words)
        local h = l.head and HEAD_H or (ITEM_H + (snip and SNIP_H or 0))
        if used + h > RES_H - 30 then break end
        n = n + 1
        local r = Row(n)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", results.view, "TOPLEFT", 0, y)
        r:SetPoint("TOPRIGHT", results.view, "TOPRIGHT", 0, y)
        r:SetHeight(h)
        r.entry = l.entry
        r.text:ClearAllPoints()
        if l.head then
            r.text:SetFontObject("GameFontNormalSmall")
            r.text:SetPoint("BOTTOMLEFT", 10, 4)
            r.text:SetPoint("RIGHT", -10, 0)
            r.text:SetText(l.head)
            r.text:SetTextColor(A[1], A[2], A[3], 0.9)
            r.snip:Hide()
            r.line:Show()
            r:EnableMouse(false)
            r.hl:Hide()
        else
            r.text:SetFontObject("GameFontHighlight")
            r.text:SetPoint("TOPLEFT", 22, -4)
            r.text:SetPoint("RIGHT", -10, 0)
            r.text:SetText(Highlight(l.entry.text, words))
            r.text:SetTextColor(1, 1, 1)
            r.snip:ClearAllPoints()
            r.snip:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
            r.snip:SetPoint("RIGHT", -10, 0)
            r.snip:SetText(snip and Highlight(snip, words) or "")
            r.snip:SetShown(snip and true or false)
            r.line:Hide()
            r:EnableMouse(true)
            r.hl:Show()
        end
        r:Show()
        y, used = y - h, used + h
    end
    for i = n + 1, #pool do pool[i]:Hide() end
    local count = #found
    results.empty:SetShown(count == 0)
    results.more:SetText(count == 0 and "" or
        (count == 1 and "1 setting" or ("%d settings"):format(count)) .. ((first > 1 or first + n - 1 < #lines) and "  -  scroll for more" or ""))
    results:SetHeight(math.max(56, used + 36))
    results:SetShown(#(box:GetText() or "") >= 2)
end

local function Query()
    found = ns.SearchSettings(box:GetText())
    first = 1
    Render()
end

function ns.BuildConfigSearch(w)
    box = UI.EditBox(w, 240, "Search settings", function() Go(found[1]) end)
    box:SetPoint("TOPRIGHT", w, "TOPRIGHT", -36, -11)
    box.mmtNoSearch = true
    box:HookScript("OnEditFocusGained", function()
        BuildIndex()
        if #(box:GetText() or "") >= 2 then Query() end
    end)
    box:HookScript("OnTextChanged", function() Query() end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        if results then results:Hide() end
    end)
    UI.Tooltip(box, "Search settings", "Finds a setting on any page - MMT's and every module's - by the start of the words in its name or its tooltip. Click a result (or Enter for the first) to go there: its page and tab open and it flashes. Esc clears.")

    -- its own layer above the settings window: the page's texts never show through it
    results = CreateFrame("Frame", nil, w)
    results.mmtNoSearch = true
    results:SetFrameStrata("FULLSCREEN_DIALOG")
    results:SetToplevel(true)
    results:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -4)
    results:SetWidth(RES_W)
    results:EnableMouse(true)
    results:EnableMouseWheel(true)
    results:SetScript("OnMouseWheel", function(_, delta) first = first - delta * 2; Render() end)
    UI.Fill(results, 0.045, 0.045, 0.055, 1)
    UI.Border(results, A[1], A[2], A[3], 0.6)
    results.view = CreateFrame("Frame", nil, results)
    results.view:SetPoint("TOPLEFT", 0, 0)
    results.view:SetPoint("BOTTOMRIGHT", 0, 24)
    results.empty = UI.Label(results, "Nothing found.")
    results.empty:SetPoint("TOPLEFT", 12, -12)
    results.empty:SetTextColor(0.6, 0.6, 0.6)
    local foot = results:CreateTexture(nil, "ARTWORK")
    foot:SetColorTexture(1, 1, 1, 0.06)
    foot:SetHeight(1)
    foot:SetPoint("BOTTOMLEFT", 8, 22); foot:SetPoint("BOTTOMRIGHT", -8, 22)
    results.more = UI.Label(results, "", "GameFontHighlightSmall")
    results.more:SetPoint("BOTTOMLEFT", 12, 6)
    results.more:SetTextColor(0.5, 0.5, 0.5)
    results:Hide()
    w:HookScript("OnHide", function() if results then results:Hide() end end)
end
