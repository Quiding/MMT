-- MMT: "New mail" in the Info window. Every client sends with the heartbeat
-- whether its character has unread mail waiting ("ml=1"; nothing without), and
-- right away when that changes (at most every 10 seconds). The piece "New mail"
-- (off by default) shows a letter for those characters.

local _, ns = ...

local LETTER = "|TInterface\\Minimap\\Tracking\\Mailbox:0|t"

local function OwnMail()
    if not HasNewMail then return false end
    local ok, v = pcall(HasNewMail)
    return ok and not ns.IsSecret(v) and v and true or false
end

local lastSent
ns.CoreHeartbeat("ml", function()
    local v = OwnMail() and "1" or nil
    lastSent = v or "0"
    return v
end)

function ns.HasMail(key)
    if ns.IsSelf(key) then return OwnMail() end
    local s = ns.status[key]
    return s and s.ext and s.ext.ml == "1" or false
end

ns.RegisterXPPiece{ id = "mail", title = "New mail", side = "RIGHT", on = false, before = "layer",
    icon = "START", sample = LETTER,
    tip = "A letter for characters with unread mail waiting at a mailbox.",
    text = function(key)
        if ns.HasMail(key) then return LETTER end
        return ""
    end }

-- mail arrived / read: tell the team (only a change, at most every 10 seconds)
local lastAt, pending = 0, false
local function SendIfChanged()
    pending = false
    if not ns.ready then return end
    local v = OwnMail() and "1" or "0"
    if v == lastSent then return end
    local wait = 10 - (GetTime() - lastAt)
    if wait > 0 then pending = true C_Timer.After(wait, SendIfChanged) return end
    lastAt = GetTime()
    ns.BroadcastXP(true)
end
ns.On("UPDATE_PENDING_MAIL", function()
    if pending then return end
    pending = true
    C_Timer.After(1, SendIfChanged)
end)
