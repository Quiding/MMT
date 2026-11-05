-- MMT Loot Distribution: sparkles (or a beam of light) on the herb, ore vein
-- or skinnable corpse in front of you.
--
-- The game tells addons nothing about the objects around you, except the one
-- the interact key would pick ("softinteract": close by, in front of you).
-- With the game's nameplate for that target switched on, the nameplate is a
-- frame that follows the object in the 3D world, so a frame anchored to it
-- stays on the object as you move. While "Sparkles" is on, this file
-- switches on (out of combat) the game settings for that nameplate and its
-- icon and lets the interact key look a bit farther, keeping each value
-- from before; they are put back when it is off again (unless they were
-- changed by hand in the meantime). Stored per character in
-- MMTDB.ldSparkleCVars[team key].
--
-- What sparkles (each only when you know the profession):
--   herbs (Herbalism) and ore veins (Mining): a list of the known names,
--     names learned when you gather something (the target of the cast),
--     and the object's tooltip ("Requires Herbalism (65)")
--   corpses: dead creatures whose tooltip says they can be skinned (or
--     gathered with Herbalism / Mining), until you did it
--   other world objects (optional), each kind on or off: quest objects (blue),
--     mailboxes, chests & containers, fishing pools, corpses with loot, and
--     everything else the interact key picks (white). Quest objects: also
--     corpses with loot a quest still wants. The tooltip's quest rows say so
--     (yours and each group member's progress, "2/6 Pyrewood Shackle"), only
--     while an objective is not done; kill objectives on a corpse don't count
-- Colour by skill: orange, yellow, green (like recipes), grey once it gives
-- no skill-ups any more, red when the skill is too low; or one colour.
--
-- The game's plate for an object shows a name and a bar: made see-through
-- (alpha only, put back when the plate shows something else), and the
-- game's icon too unless a game controller is in use. Nothing in combat:
-- the plate may go to the mob attacking you, so everything comes back
-- first. No OnUpdate: the soft target and nameplate events say when to
-- look again; the twinkle and the pulse are animations the game plays.

local _, mod = ...
local MMT = MMT
local M = mod.M

local UNIT = "softinteract"
local MEDIA = "Interface\\AddOns\\MMT_LootDistribution\\Media\\"
local S = {}
mod.Sparkles = S

-- settings (M.db), defaults in Module.lua: sparkles, sparkleStyle,
-- sparkleHerbs, sparkleOre, sparkleCorpses, sparkleObjects, sparkleColors, sparkleColor,
-- sparkleSize, sparkleHeight, sparkleHideIcon
local function On() return M.enabled and M.db.sparkles == true end

local function Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    if MMT.IsSecret(a) then a = nil end
    if MMT.IsSecret(b) then b = nil end
    return a, b, c
end
local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

---------------------------------------------------------------------------
-- Game settings
---------------------------------------------------------------------------
-- value: what is set; only raised (a higher value of yours stays).
-- moves: switched back and forth as you face creatures and objects
S.CVARS = {
    { name = "SoftTargetInteract", value = 3 },            -- interact target: always
    { name = "SoftTargetNameplateInteract", value = 1, moves = true },
    { name = "SoftTargetInteractRange", value = 15 },      -- yards
    { name = "SoftTargetInteractArc", value = 2 },         -- all around you
    { name = "SoftTargetIconGameObject", value = 1 },
    { name = "SoftTargetIconInteract", value = 1 },
}

local function GetCV(name)
    if C_CVar and C_CVar.GetCVar then return Safe(C_CVar.GetCVar, name) end
    return Safe(GetCVar, name)
end
local function SetCV(name, value)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if not set then return false end
    return pcall(set, name, tostring(value))
end

local function Saved()
    MMTDB.ldSparkleCVars = MMTDB.ldSparkleCVars or {}
    local me = MMT.PlayerFull()
    MMTDB.ldSparkleCVars[me] = MMTDB.ldSparkleCVars[me] or {}
    return MMTDB.ldSparkleCVars[me]
end

local pendingApply, pendingRestore
function S.ApplySettings()
    if not On() then return end
    if InCombat() then pendingApply = true return end
    pendingApply = nil
    local saved = Saved()
    for _, c in ipairs(S.CVARS) do
        local cur = GetCV(c.name)
        if cur ~= nil and (tonumber(cur) or 0) < c.value then
            if saved[c.name] == nil then saved[c.name] = { old = cur } end
            saved[c.name].set = tostring(c.value)
            SetCV(c.name, c.value)
        end
    end
end

function S.RestoreSettings()
    local all = MMTDB.ldSparkleCVars
    local saved = all and all[MMT.PlayerFull()]
    if not saved or next(saved) == nil then return end
    if InCombat() then pendingRestore = true return end
    pendingRestore = nil
    for _, c in ipairs(S.CVARS) do
        local s = saved[c.name]
        if s then
            local cur = GetCV(c.name)
            -- changed by hand since: yours (the one MMT moves itself always goes back)
            if c.moves or cur == s.set then SetCV(c.name, s.old) end
            saved[c.name] = nil
        end
    end
    all[MMT.PlayerFull()] = nil
end

-- MMT switched the interact nameplate on: then its plates are MMT's doing
local function OwnsPlates()
    local all = MMTDB.ldSparkleCVars
    local saved = all and all[MMT.PlayerFull()]
    return saved and saved.SoftTargetNameplateInteract ~= nil
end

local function Controller()
    if C_GamePad and C_GamePad.IsEnabled and Safe(C_GamePad.IsEnabled) == true then return true end
    return GetCV("GamePadEnable") == "1"
end

---------------------------------------------------------------------------
-- Professions and nodes
---------------------------------------------------------------------------
local SKILL_LINES = { [182] = "Herbalism", [186] = "Mining", [393] = "Skinning" }
local ENGLISH = { Herbalism = "Herbalism", Mining = "Mining", Skinning = "Skinning" }

-- { Herbalism = rank, ... } of this character, plus the shown (localized) names
function S.Skills()
    local skills, names = {}, {}
    if GetProfessions and GetProfessionInfo then
        local list = { Safe(GetProfessions) }
        for i = 1, 5 do
            local index = list[i]
            if index then
                local ok, name, _, rank, _, _, _, line = pcall(GetProfessionInfo, index)
                local key = ok and SKILL_LINES[line]
                if key and not MMT.IsSecret(rank) then skills[key] = rank or 1; names[key] = name end
            end
        end
    end
    if next(skills) == nil and GetNumSkillLines and GetSkillLineInfo then
        for i = 1, (Safe(GetNumSkillLines) or 0) do
            local ok, name, header, _, rank = pcall(GetSkillLineInfo, i)
            local key = ok and not header and ENGLISH[name]
            if key then skills[key] = rank or 1; names[key] = name end
        end
    end
    return skills, names
end

-- skill each node needs (the names the game shows; "Wilted Peacebloom" and
-- other names with words in front count as the node they end with)
S.NODES = {
    -- herbs
    ["peacebloom"] = { "Herbalism", 1 }, ["silverleaf"] = { "Herbalism", 1 }, ["earthroot"] = { "Herbalism", 15 },
    ["mageroyal"] = { "Herbalism", 50 }, ["briarthorn"] = { "Herbalism", 70 }, ["stranglekelp"] = { "Herbalism", 85 },
    ["bruiseweed"] = { "Herbalism", 100 }, ["wild steelbloom"] = { "Herbalism", 115 }, ["grave moss"] = { "Herbalism", 120 },
    ["kingsblood"] = { "Herbalism", 125 }, ["liferoot"] = { "Herbalism", 150 }, ["fadeleaf"] = { "Herbalism", 160 },
    ["goldthorn"] = { "Herbalism", 170 }, ["khadgar's whisker"] = { "Herbalism", 185 }, ["wintersbite"] = { "Herbalism", 195 },
    ["firebloom"] = { "Herbalism", 205 }, ["purple lotus"] = { "Herbalism", 210 }, ["arthas' tears"] = { "Herbalism", 220 },
    ["sungrass"] = { "Herbalism", 230 }, ["blindweed"] = { "Herbalism", 235 }, ["ghost mushroom"] = { "Herbalism", 245 },
    ["gromsblood"] = { "Herbalism", 250 }, ["golden sansam"] = { "Herbalism", 260 }, ["dreamfoil"] = { "Herbalism", 270 },
    ["mountain silversage"] = { "Herbalism", 280 }, ["plaguebloom"] = { "Herbalism", 285 }, ["icecap"] = { "Herbalism", 290 },
    ["black lotus"] = { "Herbalism", 300 },
    -- ore
    ["copper vein"] = { "Mining", 1 }, ["tin vein"] = { "Mining", 65 }, ["incendicite mineral vein"] = { "Mining", 65 },
    ["silver vein"] = { "Mining", 75 }, ["lesser bloodstone deposit"] = { "Mining", 75 }, ["iron deposit"] = { "Mining", 125 },
    ["indurium mineral vein"] = { "Mining", 150 }, ["gold vein"] = { "Mining", 155 }, ["mithril deposit"] = { "Mining", 175 },
    ["truesilver deposit"] = { "Mining", 230 }, ["dark iron deposit"] = { "Mining", 230 }, ["small thorium vein"] = { "Mining", 245 },
    ["rich thorium vein"] = { "Mining", 275 },
}

-- spells whose cast target is a node: what was gathered is learned
local GATHER_SPELLS = { ["Herb Gathering"] = "Herbalism", ["Herbalism"] = "Herbalism", ["Mining"] = "Mining", ["Skinning"] = "Skinning" }

local function Learned()
    M.store.nodes = M.store.nodes or {}
    return M.store.nodes
end

-- the node a name stands for: { skill, need or nil }
function S.NodeFor(name)
    if type(name) ~= "string" or name == "" then return nil end
    local lower = name:lower()
    local learned = Learned()
    local rest = lower
    for _ = 0, 3 do
        local n = S.NODES[rest]
        if n then return n[1], n[2] end
        if learned[rest] then return learned[rest], nil end
        rest = rest:match("^%S+%s+(.+)$")
        if not rest then break end
    end
end

local function TooltipLines()
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return {} end
    local data = Safe(C_TooltipInfo.GetUnit, UNIT)
    local out = {}
    for i, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
        local text = type(line) == "table" and line.leftText
        if type(text) == "string" and not MMT.IsSecret(text) and i > 1 then out[#out + 1] = text end
    end
    return out
end

-- "Requires Herbalism (65)" / "Herbalism" in the object's tooltip
local function SkillFromTooltip(names)
    for _, text in ipairs(TooltipLines()) do
        for key, shown in pairs(names) do
            if text:find(shown, 1, true) or text:find(key, 1, true) then
                return key, tonumber(text:match("(%d+)"))
            end
        end
        for key in pairs(ENGLISH) do
            if text:find(key, 1, true) then return key, tonumber(text:match("(%d+)")) end
        end
    end
end

-- corpse tooltip lines: skinnable, or to gather with herbalism / mining
local function CorpseSkill()
    local lines = {
        [UNIT_SKINNABLE_LEATHER or "Skinnable"] = "Skinning",
        [UNIT_SKINNABLE_HERB or "Requires Herbalism"] = "Herbalism",
        [UNIT_SKINNABLE_ROCK or "Requires Mining"] = "Mining",
    }
    lines["Skinnable"] = lines["Skinnable"] or "Skinning"
    for _, text in ipairs(TooltipLines()) do
        if lines[text] then return lines[text] end
    end
end

-- The quest rows of the target's tooltip. The game lists them for objects and
-- creatures (dead ones too): a QuestTitle row (line.id = quest ID), in a group
-- a QuestPlayer row per member who has the quest, then the QuestObjective
-- rows (numFulfilled / numRequired) of that member. Returns "open" when one
-- objective row is not done yet, "done" when there are rows and all are done,
-- nil without rows or when the game keeps them secret (in combat, creatures
-- inside instances). skip(questID, text): rows that don't count.
local function ReadQuestRows(skip)
    local types = Enum and Enum.TooltipDataLineType
    if not (types and types.QuestObjective and C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
    local data = Safe(C_TooltipInfo.GetUnit, UNIT)
    local lines = type(data) == "table" and data.lines
    if MMT.IsSecret(lines) or type(lines) ~= "table" then return nil end
    local state, quest
    for _, line in ipairs(lines) do
        if MMT.IsSecret(line) or type(line) ~= "table" or MMT.IsSecret(line.type) then return nil end
        if line.type == types.QuestTitle then
            quest = line.id
            if MMT.IsSecret(quest) then return nil end
        elseif line.type == types.QuestObjective then
            local text, have, need = line.leftText, line.numFulfilled, line.numRequired
            if MMT.IsSecret(text) or MMT.IsSecret(have) or MMT.IsSecret(need) then return nil end
            if not (skip and skip(quest, text)) then
                local open
                if type(have) == "number" and type(need) == "number" and need > 0 then
                    open = have < need
                else   -- no counts: "3/8" in the text, else not done
                    local h, n = (type(text) == "string" and text or ""):match("(%d+)%s*/%s*(%d+)")
                    open = not h or tonumber(h) < tonumber(n)
                end
                if open then return "open" end
                state = "done"
            end
        end
    end
    return state
end
function S.QuestRows(skip)
    local ok, state = pcall(ReadQuestRows, skip)
    return ok and state or nil
end

-- "Pyrewood Shackle: 2/6" (quest log) and "2/6 Pyrewood Shackle" (tooltip) alike
local function Bare(text)
    return (tostring(text):lower():gsub("[%d/:%(%)%%]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

-- a kill objective row on a corpse: counted when the creature died, its loot
-- has nothing more for it. The quest log tells (your own quests); for a quest
-- only a team member has: the creature's name or "slain" in the row.
local function KillRow(questID, text, unitName)
    if type(text) ~= "string" then return false end
    local bare = Bare(text)
    if type(questID) == "number" and C_QuestLog and C_QuestLog.GetQuestObjectives then
        local list = Safe(C_QuestLog.GetQuestObjectives, questID)
        for _, o in ipairs(type(list) == "table" and list or {}) do
            if type(o) == "table" and not MMT.IsSecret(o.text) and not MMT.IsSecret(o.type)
                and type(o.text) == "string" and Bare(o.text) == bare then
                return o.type == "monster"
            end
        end
    end
    if type(unitName) == "string" and unitName ~= "" and bare:find(unitName:lower(), 1, true) then return true end
    return bare:find("%f[%a]slain%f[%A]") ~= nil
end

-- skill a corpse of this level needs (Skinning and the others alike)
local function CorpseNeed(level)
    if type(level) ~= "number" or level <= 10 then return 1 end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
end

local done = {}        -- [corpse guid] = true once skinned / gathered
local pendingCast      -- { castGUID, guid, skill } of a gathering cast

---------------------------------------------------------------------------
-- What the interact key points at: { guid, skill, have, need } or nil
---------------------------------------------------------------------------
function S.Target()
    local guid = Safe(UnitGUID, UNIT)
    if type(guid) ~= "string" then return nil end
    local skills, names = S.Skills()
    if guid:find("^GameObject%-") then
        local name = Safe(UnitName, UNIT)
        local skill, need = S.NodeFor(name)
        if not skill then skill, need = SkillFromTooltip(names) end
        local node = (skill == "Herbalism" and M.db.sparkleHerbs) or (skill == "Mining" and M.db.sparkleOre)
        if node and skills[skill] then
            return { guid = guid, skill = skill, have = skills[skill], need = need }
        end
        -- any other object the interact key picks, by kind (each on or off);
        -- a node of a profession you don't have (or one switched off) isn't one of them
        if M.db.sparkleObjects and not skill then
            local kind = S.ObjectKind(name)
            if S.KindOn(kind) then return { guid = guid, skill = "Object", other = kind } end
        end
        return nil
    end
    if done[guid] or not guid:find("^Creature%-") or Safe(UnitIsDead, UNIT) ~= true then return nil end
    local hasLoot = CanLootUnit and Safe(CanLootUnit, guid)
    -- a corpse with loot a quest of yours or a group member still wants (before
    -- skinning: the loot comes first); kill objectives don't count
    if M.db.sparkleObjects and S.KindOn("quest") and hasLoot == true then
        local unitName = Safe(UnitName, UNIT)
        if S.QuestRows(function(quest, text) return KillRow(quest, text, unitName) end) == "open" then
            return { guid = guid, skill = "Object", other = "quest", corpse = true }
        end
    end
    if M.db.sparkleCorpses then
        local skill = CorpseSkill()
        if skill and skills[skill] then
            local level = Safe(UnitLevel, UNIT)
            return { guid = guid, skill = skill, have = skills[skill], need = CorpseNeed(level), corpse = true }
        end
    end
    -- a corpse with loot left on it
    if M.db.sparkleObjects and S.KindOn("loot") and hasLoot == true then
        return { guid = guid, skill = "Object", other = "loot", corpse = true }
    end
    return nil
end

-- kinds of other world objects; settings in M.db.sparkleKinds[kind]
S.KINDS = {
    { "quest", "Quest objects" }, { "mailbox", "Mailboxes" }, { "chest", "Chests & containers" },
    { "fishing", "Fishing pools" }, { "loot", "Corpses with loot" }, { "other", "Everything else" },
}
local CHEST_WORDS = { "chest", "footlocker", "strongbox", "lockbox", "coffer", "trunk", "cache", "treasure", "crate", "barrel" }
local FISHING_WORDS = { "school", "pool", "wreckage", "floating debris", "oil spill" }

function S.KindOn(kind)
    local kinds = M.db.sparkleKinds
    return kind ~= nil and (type(kinds) ~= "table" or kinds[kind] ~= false)
end

local function HasWord(lower, words)
    for _, w in ipairs(words) do
        if lower:find("%f[%a]" .. w) then return true end
    end
    return false
end

-- what kind of object the interact key points at: quest, mailbox, chest, fishing or other
function S.ObjectKind(name)
    -- the quest rows decide when the game shows them: quest only while some
    -- objective (yours or a group member's) is not done yet
    local rows = S.QuestRows()
    if rows == "open" then return "quest" end
    if rows == nil and C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest and Safe(C_QuestLog.UnitIsRelatedToActiveQuest, UNIT) == true then
        return "quest"
    end
    for _, text in ipairs(TooltipLines()) do
        local have, need = text:match("(%d+)%s*/%s*(%d+)")
        if have and tonumber(have) < tonumber(need) then return "quest" end
    end
    local lower = type(name) == "string" and name:lower() or ""
    local mailbox = type(MAILBOX) == "string" and not MMT.IsSecret(MAILBOX) and MAILBOX:lower() or "mailbox"
    if lower:find(mailbox, 1, true) or lower:find("mailbox", 1, true) then return "mailbox" end
    if HasWord(lower, FISHING_WORDS) then return "fishing" end
    if HasWord(lower, CHEST_WORDS) then return "chest" end
    return "other"
end

---------------------------------------------------------------------------
-- Colours
---------------------------------------------------------------------------
S.COLORS = {
    red = { 1, 0.25, 0.25 }, orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 },
    green = { 0.25, 0.85, 0.25 }, grey = { 0.65, 0.65, 0.65 }, white = { 1, 1, 1 },
    quest = { 0.3, 0.65, 1 },
}
local GOLD = { r = 1, g = 0.84, b = 0.36 }

function S.ColorFor(t)
    local c = M.db.sparkleColor or GOLD
    if M.db.sparkleColors and t and t.other then return t.other == "quest" and S.COLORS.quest or S.COLORS.white end
    if not M.db.sparkleColors or not t or not t.need then return { c.r, c.g, c.b } end
    local over = (t.have or 0) - t.need
    if over < 0 then return S.COLORS.red end
    if over < 25 then return S.COLORS.orange end
    if over < 50 then return S.COLORS.yellow end
    if over < 100 then return S.COLORS.green end
    return S.COLORS.grey
end

---------------------------------------------------------------------------
-- The frame: sparkles and a beam
---------------------------------------------------------------------------
local SPARKS = {   -- x, y (pixels from the anchor), size, start delay
    { -24, 12, 18, 0.0 }, { 22, 20, 14, 0.45 }, { 16, -6, 12, 0.9 },
    { -10, -12, 10, 0.7 }, { 4, 32, 13, 0.25 }, { -28, 28, 9, 1.1 },
}
local frame, sparks, beam, tint

local function Alpha(group, from, to, duration, delay, order, smoothing)
    local a = group:CreateAnimation("Alpha")
    a:SetFromAlpha(from) a:SetToAlpha(to) a:SetDuration(duration)
    if delay then a:SetStartDelay(delay) end
    if order then a:SetOrder(order) end
    if smoothing then a:SetSmoothing(smoothing) end
    return a
end

local function Texture(parent, file, w, h, alpha)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(MEDIA .. file)
    t:SetSize(w, h)
    pcall(t.SetBlendMode, t, "ADD")
    t.baseAlpha = alpha
    return t
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "MMTLootSparkle", UIParent)
    frame:SetSize(80, 60)
    frame:SetFrameStrata("BACKGROUND")
    frame:EnableMouse(false)
    frame:Hide()
    sparks = {}
    for _, s in ipairs(SPARKS) do
        local h = CreateFrame("Frame", nil, frame)
        h:SetSize(s[3] * 2, s[3] * 2)
        h:SetPoint("CENTER", frame, "CENTER", s[1], s[2])
        local glow = Texture(h, "Glow", s[3], s[3], 0.45)
        glow:SetPoint("CENTER")
        local star = Texture(h, "Star", s[3] * 2, s[3] * 2, 1)
        star:SetPoint("CENTER")
        local g = h:CreateAnimationGroup()
        g:SetLooping("REPEAT")
        Alpha(g, 0, 1, 0.8, s[4], 1, "OUT")
        Alpha(g, 1, 0, 0.8, nil, 2, "IN")
        sparks[#sparks + 1] = { holder = h, anim = g, textures = { glow, star } }
    end
    local b = CreateFrame("Frame", nil, frame)
    b:SetSize(66, 240)
    b:SetPoint("BOTTOM", frame, "CENTER", 0, -6)
    local column = Texture(b, "Beam", 22, 240, 1)
    column:SetPoint("BOTTOM")
    local foot = Texture(b, "Glow", 66, 30, 0.8)
    foot:SetPoint("CENTER", b, "BOTTOM", 0, 4)
    local g = b:CreateAnimationGroup()
    g:SetLooping("BOUNCE")
    Alpha(g, 1, 0.6, 1.2, nil, nil, "IN_OUT")
    beam = { holder = b, anim = g, textures = { column, foot } }
    return frame
end

local function Tint(c)
    local key = c[1] .. ":" .. c[2] .. ":" .. c[3]
    if tint == key then return end
    tint = key
    local all = { beam }
    for _, s in ipairs(sparks) do all[#all + 1] = s end
    for _, light in ipairs(all) do
        for _, t in ipairs(light.textures) do t:SetVertexColor(c[1], c[2], c[3], t.baseAlpha) end
    end
end

local shownOn
local function Hide()
    shownOn = nil
    if not frame then return end
    for _, s in ipairs(sparks) do s.anim:Stop() end
    beam.anim:Stop()
    frame:ClearAllPoints()
    frame:Hide()
end

local function Icon(plate)
    local uf = plate and plate.UnitFrame
    local icon = uf and uf.SoftTargetFrame
    if type(icon) == "table" and icon.GetObjectType then return icon end
end

local function Show(plate, color)
    Build()
    Tint(color)
    local scale = math.max(0.3, (M.db.sparkleSize or 100) / 100)
    frame:SetScale(scale)
    frame:ClearAllPoints()
    local icon = Icon(plate)
    -- the game's icon floats above the object: down onto it by the plate's size
    local ratio = 1
    local ps, us = Safe(plate.GetEffectiveScale, plate), Safe(UIParent.GetEffectiveScale, UIParent)
    if type(ps) == "number" and type(us) == "number" and us > 0 then ratio = math.min(2, math.max(0.25, ps / us)) end
    local drop = (70 - (M.db.sparkleHeight or 0)) * ratio / scale
    local ok
    if icon then ok = pcall(frame.SetPoint, frame, "CENTER", icon, "CENTER", 0, -drop)
    else ok = pcall(frame.SetPoint, frame, "CENTER", plate, "BOTTOM", 0, ((M.db.sparkleHeight or 0) - 10) / scale) end
    if not ok then Hide() return end
    shownOn = plate
    local isBeam = M.db.sparkleStyle == "BEAM"
    beam.holder:SetShown(isBeam)
    if isBeam then if not beam.anim:IsPlaying() then beam.anim:Play() end else beam.anim:Stop() end
    for _, s in ipairs(sparks) do
        s.holder:SetShown(not isBeam)
        if isBeam then s.anim:Stop() elseif not s.anim:IsPlaying() then s.anim:Play() end
    end
    frame:Show()
end

---------------------------------------------------------------------------
-- The game's plate: see-through parts (alpha only, given back)
---------------------------------------------------------------------------
local veiled = setmetatable({}, { __mode = "k" })   -- [region] = alpha before

local function Plate()
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local plate = Safe(C_NamePlate.GetNamePlateForUnit, UNIT)
    if type(plate) ~= "table" then return nil end
    if plate.IsForbidden and plate:IsForbidden() then return nil end
    return plate
end

local function Unveil(region)
    local a = veiled[region]
    veiled[region] = nil
    if a then pcall(region.SetAlpha, region, a) end
end
function S.UnveilAll()
    local list = {}
    for r in pairs(veiled) do list[#list + 1] = r end
    for _, r in ipairs(list) do Unveil(r) end
end

-- t: the target (nil = nothing wanted on the plate)
local function Veil(plate, t)
    if InCombat() then return end
    local want = {}
    if plate and t and OwnsPlates() then
        local uf = plate.UnitFrame
        local icon = Icon(plate)
        if uf then
            for _, method in ipairs({ "GetRegions", "GetChildren" }) do
                local ok, list = pcall(function() return { uf[method](uf) } end)
                for _, r in ipairs(ok and list or {}) do
                    -- a corpse keeps its name: the game moves it from the head onto the plate
                    local isName = r == uf.name or (r.GetObjectType and r:GetObjectType() == "FontString")
                    if r ~= icon and not (t.corpse and isName) then want[r] = true end
                end
            end
        end
        if icon and M.db.sparkleHideIcon and not Controller() then want[icon] = true end
    end
    for r in pairs(veiled) do if not want[r] then Unveil(r) end end
    for r in pairs(want) do
        if veiled[r] == nil then veiled[r] = Safe(r.GetAlpha, r) or 1 end
        pcall(r.SetAlpha, r, 0)
    end
end

-- the interact plate only for what sparkles: anything else keeps your own
-- setting (on a creature the game would move its name from the head onto a
-- plate, an object would get a name and a bar)
local function FitPlate(t)
    if InCombat() or not OwnsPlates() then return end
    local want = t and "1" or Saved().SoftTargetNameplateInteract.old
    if GetCV("SoftTargetNameplateInteract") ~= want then SetCV("SoftTargetNameplateInteract", want) end
end

---------------------------------------------------------------------------
-- Looking again
---------------------------------------------------------------------------
local lastState = "off"
function S.Refresh()
    if not On() then
        Hide() S.UnveilAll()
        lastState = "off"
        return lastState
    end
    local ok, t = pcall(S.Target)
    if not ok then t = nil end
    pcall(FitPlate, t)
    local plate = t and Plate()
    pcall(Veil, plate, t)
    if t and plate then
        Show(plate, S.ColorFor(t))
        lastState = ("shown %s need=%s have=%s"):format(t.skill, tostring(t.need), tostring(t.have))
    else
        Hide()
        lastState = t and "no plate" or "nothing"
    end
    return lastState
end

-- the game fills in a plate right after the events: look once more then
local again
local function RefreshSoon()
    S.Refresh()
    if not again then
        again = true
        C_Timer.After(0.1, function() again = nil S.Refresh() end)
    end
end

-- switched on / off (settings page, profile, module)
function S.Update()
    if On() then S.ApplySettings() else Hide() S.UnveilAll() S.RestoreSettings() end
    S.Refresh()
end

M:On("PLAYER_SOFT_INTERACT_CHANGED", RefreshSoon)
M:On("NAME_PLATE_UNIT_ADDED", RefreshSoon)
M:On("NAME_PLATE_UNIT_REMOVED", function() if shownOn then RefreshSoon() end end)
M:On("PLAYER_REGEN_DISABLED", function() S.UnveilAll() end)
MMT.On("PLAYER_REGEN_ENABLED", function()
    if pendingApply then S.ApplySettings() end
    if pendingRestore then S.RestoreSettings() end
    if M.enabled then RefreshSoon() end
end)
M:On("PLAYER_ENTERING_WORLD", function() S.Update() end)
MMT.Listen("PROFILE_CHANGED", function() S.Update() end)

-- learning node names, and corpses that are done
M:On("UNIT_SPELLCAST_SENT", function(unit, target, castGUID, spellID)
    if unit ~= "player" or MMT.IsSecret(target) or MMT.IsSecret(spellID) then return end
    local name = C_Spell and C_Spell.GetSpellName and Safe(C_Spell.GetSpellName, spellID)
        or (GetSpellInfo and Safe(GetSpellInfo, spellID))
    local skill = name and GATHER_SPELLS[name]
    if not skill then return end
    local guid = Safe(UnitGUID, UNIT)
    pendingCast = { castGUID = castGUID, guid = guid, skill = skill }
    if type(target) == "string" and target ~= "" and type(guid) == "string" and guid:find("^GameObject%-")
        and (skill == "Herbalism" or skill == "Mining") and not S.NodeFor(target) then
        Learned()[target:lower()] = skill
        M:Debug("sparkles: learned node %s (%s)", MMT.Repr(target), skill)
    end
end)
M:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID)
    if unit ~= "player" or not pendingCast or MMT.IsSecret(castGUID) or castGUID ~= pendingCast.castGUID then return end
    local guid = pendingCast.guid
    pendingCast = nil
    if type(guid) == "string" and guid:find("^Creature%-") then
        done[guid] = true
        RefreshSoon()
    end
end)

-- module on / off
do
    local enable, disable = M.OnEnable, M.OnDisable
    M.OnEnable = function(...)
        if enable then enable(...) end
        S.Update()
    end
    M.OnDisable = function(...)
        if disable then disable(...) end
        Hide() S.UnveilAll() S.RestoreSettings()
    end
end

function S.Report(add)
    local saved = MMTDB.ldSparkleCVars and MMTDB.ldSparkleCVars[MMT.PlayerFull()]
    local cv = {}
    for _, c in ipairs(S.CVARS) do
        local s = saved and saved[c.name]
        cv[#cv + 1] = ("%s=%s%s"):format(c.name, tostring(GetCV(c.name)), s and (" (was " .. tostring(s.old) .. ")") or "")
    end
    local skills = S.Skills()
    local learned = 0
    for _ in pairs(Learned()) do learned = learned + 1 end
    add(("sparkles: on=%s style=%s herbs=%s ore=%s corpses=%s objects=%s colors=%s size=%s height=%s hideIcon=%s state=%s"):format(
        tostring(M.db.sparkles), tostring(M.db.sparkleStyle), tostring(M.db.sparkleHerbs), tostring(M.db.sparkleOre),
        tostring(M.db.sparkleCorpses), tostring(M.db.sparkleObjects), tostring(M.db.sparkleColors), tostring(M.db.sparkleSize), tostring(M.db.sparkleHeight),
        tostring(M.db.sparkleHideIcon), lastState))
    local kinds = {}
    for _, k in ipairs(S.KINDS) do kinds[#kinds + 1] = k[1] .. "=" .. tostring(S.KindOn(k[1])) end
    add("  object kinds: " .. table.concat(kinds, " ") .. "  quest rows: " .. tostring(S.QuestRows()))
    add(("  skills: Herbalism=%s Mining=%s Skinning=%s  learned nodes=%d  controller=%s"):format(
        tostring(skills.Herbalism), tostring(skills.Mining), tostring(skills.Skinning), learned, tostring(Controller())))
    add("  game: " .. table.concat(cv, " "))
    local guid = Safe(UnitGUID, UNIT)
    add(("  interact target: %s %s plate=%s tooltip=[%s]"):format(MMT.Repr(Safe(UnitName, UNIT)), tostring(guid),
        tostring(Plate() ~= nil), table.concat(TooltipLines(), " | ")))
end
