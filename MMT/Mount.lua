-- MMT: mount and dismount with the leader (as in EMA and MAMA).
--
-- The leader (the FTL leader; without one online, the group leader if in the team, else the first online team member) tells the team
-- when it starts summoning a mount (MOUNT:<mount ID>) and when it dismounts
-- (DISMOUNT). Team members then summon the same mount if they have it, else
-- one of the same kind (ground / flying / ...), else a random favourite; and
-- dismount, but never in the air. Holding Shift while mounting or
-- dismounting keeps it to the leader.
--
-- Key bindings (Bindings.xml), pressed on the leader: "Mount team: random
-- favourite", "Mount team: chosen mount" (Automation page) and "Dismount team".
-- They work even with "Mount up / Dismount with the leader" off: the leader then
-- sends MOUNTX / DISMOUNTX, which team members follow regardless of those options
-- (MMT 1.2.0+). Pressed while mounted, the mount keys dismount the team.

local _, ns = ...

local function Cfg() return ns.db and ns.db.mount end
local function Safe(fn, ...) if fn then return ns.Safe(fn, ...) end end

local function InCombat()
    return InCombatLockdown() or Safe(UnitAffectingCombat, "player") or false
end

local function Mounted() return Safe(IsMounted) and true or false end

---------------------------------------------------------------------------
-- Mount journal helpers (retail mount system)
---------------------------------------------------------------------------

local function MountFromSpell(spellID)
    local J = C_MountJournal
    if not (J and spellID) or ns.IsSecret(spellID) then return nil end
    if J.GetMountFromSpell then
        local id = Safe(J.GetMountFromSpell, spellID)
        if id then return id end
    end
    for _, id in ipairs((J.GetMountIDs and J.GetMountIDs()) or {}) do
        local _, mountSpell = J.GetMountInfoByID(id)
        if mountSpell == spellID then return id end
    end
end

local function ActiveMount()
    local J = C_MountJournal
    if not J then return nil end
    for _, id in ipairs((J.GetMountIDs and J.GetMountIDs()) or {}) do
        local _, _, _, active = J.GetMountInfoByID(id)
        if active then return id end
    end
end

local function MountType(id)
    local J = C_MountJournal
    if not (J and J.GetMountInfoExtraByID) then return nil end
    local _, _, _, _, mountType = J.GetMountInfoExtraByID(id)
    return mountType
end

-- the mount to summon here for the leader's mount: same, same kind, or 0 (random favourite)
local function ChooseMount(leaderMount)
    local J = C_MountJournal
    if not J then return nil end
    local _, _, _, _, usable = J.GetMountInfoByID(leaderMount)
    if usable then return leaderMount end
    local kind = MountType(leaderMount)
    local fallback
    for _, id in ipairs((J.GetMountIDs and J.GetMountIDs()) or {}) do
        local _, _, _, _, isUsable, _, isFavorite, _, _, hidden, collected = J.GetMountInfoByID(id)
        if isUsable and collected ~= false and not hidden and MountType(id) == kind then
            if isFavorite then return id end
            fallback = fallback or id
        end
    end
    return fallback or 0
end

---------------------------------------------------------------------------
-- Leader: tell the team
---------------------------------------------------------------------------
local following = false   -- this client mounts because the leader did: don't send
local lastSent = 0
local wasMounted = false

local function IsLeader() return ns.IsNoticeLeaderHere and ns.IsNoticeLeaderHere() end

local forced = 0   -- a team key was pressed (until this time): send even with the options off

local function SendMount(mountID)
    local cfg = Cfg()
    local force = GetTime() < forced
    if not cfg or following or not mountID or mountID == 0 or not IsLeader() then return end
    if not force and (not cfg.mount or IsShiftKeyDown()) then return end
    if GetTime() - lastSent < 3 then return end
    lastSent = GetTime()
    ns.Debug("mount: leader mounts %s, telling the team%s", tostring(mountID), force and " (team key)" or "")
    ns.SendAlert((force and "MOUNTX:" or "MOUNT:") .. mountID)
end

ns.On("UNIT_SPELLCAST_START", function(unit, castGUID, spellID)
    if unit ~= "player" then return end
    local id = MountFromSpell(spellID)
    if id then SendMount(id) end
end)

ns.On("PLAYER_MOUNT_DISPLAY_CHANGED", function()
    local mounted = Mounted()
    local cfg = Cfg()
    if mounted and not wasMounted then
        -- mounts without a cast (or a cast event the game hid): send now
        if GetTime() - lastSent >= 3 then SendMount(ActiveMount()) end
    elseif not mounted and wasMounted then
        if cfg and cfg.dismount and not following and IsLeader() and not IsShiftKeyDown()
            and not Safe(UnitOnTaxi, "player") then
            ns.Debug("mount: leader dismounted, telling the team")
            ns.SendAlert("DISMOUNT")
        end
    end
    wasMounted = mounted
end)
ns.On("PLAYER_ENTERING_WORLD", function() wasMounted = Mounted() end)

---------------------------------------------------------------------------
-- Team members
---------------------------------------------------------------------------
-- the leader is near enough to see (when in a group)
local function LeaderNearby(key)
    local unit = ns.UnitForMember and ns.UnitForMember(key)
    if not unit then return true end
    local visible = Safe(UnitIsVisible, unit)
    return visible ~= false
end

local function MountUp(mountID, key)
    local J = C_MountJournal
    if Mounted() or InCombat() then return end
    if Safe(UnitIsDeadOrGhost, "player") or Safe(IsIndoors) then return end
    if not LeaderNearby(key) then return end
    local id = ChooseMount(mountID)
    if not id then return end
    following = true
    local ok, err = pcall(J.SummonByID, id)
    C_Timer.After(3, function() following = false end)
    ns.Debug("mount: following %s -> SummonByID(%s) %s %s", ns.Repr(key), tostring(id), tostring(ok), tostring(err or ""))
end

local function DismountHere(key)
    if not Mounted() then return end
    if Safe(IsFlying) then
        ns.Debug("mount: not dismounting in the air")
        return
    end
    following = true
    local ok, err = pcall(Dismount)
    C_Timer.After(1, function() following = false end)
    ns.Debug("mount: following %s -> Dismount %s %s", ns.Repr(key), tostring(ok), tostring(err or ""))
end

ns.Listen("TEAM_MESSAGE", function(key, sender, text)
    local J = C_MountJournal
    local cfg = Cfg()
    if not cfg then return end
    local id = text:match("^MOUNT:(%d+)$")
    if id then
        if cfg.mount and J and J.SummonByID then MountUp(tonumber(id), key) end
        return
    end
    if text == "DISMOUNT" and cfg.dismount and Dismount then DismountHere(key) end
    -- the leader pressed a team key: followed with the options off too
    id = text:match("^MOUNTX:(%d+)$")
    if id then
        if J and J.SummonByID then MountUp(tonumber(id), key) end
        return
    end
    if text == "DISMOUNTX" and Dismount then DismountHere(key) end
end)

---------------------------------------------------------------------------
-- Key bindings (pressed on the leader; on anyone else they mount that character)
---------------------------------------------------------------------------
-- collected mounts usable by this character, sorted by name: { { id, name }, ... }
function ns.MountChoices()
    local J = C_MountJournal
    local list = {}
    if not (J and J.GetMountIDs and J.GetMountInfoByID) then return list end
    for _, id in ipairs(J.GetMountIDs() or {}) do
        local name, _, _, _, _, _, _, _, _, hidden, collected = J.GetMountInfoByID(id)
        if collected and not hidden and type(name) == "string" and not ns.IsSecret(name) then
            list[#list + 1] = { id = id, name = name }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function TeamDismount()
    forced = GetTime() + 2
    if IsLeader() then
        ns.Debug("mount: team key, dismounting the team")
        ns.SendAlert("DISMOUNTX")
    end
    if Mounted() and not Safe(IsFlying) then
        following = true   -- the dismount event mustn't send a second DISMOUNT
        pcall(Dismount)
        C_Timer.After(1, function() following = false end)
    end
end

local function TeamMount(id)
    local J = C_MountJournal
    if not (J and J.SummonByID) then return end
    if Mounted() then TeamDismount() return end
    if InCombat() then ns.Print("Can't mount in combat.") return end
    forced = GetTime() + 5
    lastSent = 0
    local ok, err = pcall(J.SummonByID, id or 0)
    ns.Debug("mount: team key -> SummonByID(%s) %s %s", tostring(id or 0), tostring(ok), tostring(err or ""))
end

function MMT_MountTeamRandom() TeamMount(0) end   -- 0 = a random favourite
function MMT_MountTeamChosen()
    local cfg = Cfg()
    local id = cfg and cfg.chosen or 0
    local J = C_MountJournal
    if id ~= 0 and J and J.GetMountInfoByID then
        local _, _, _, _, usable = J.GetMountInfoByID(id)
        if not usable then id = 0 end   -- can't use it here (e.g. a flying mount on the ground): a random favourite
    end
    TeamMount(id)
end
function MMT_DismountTeam() TeamDismount() end
