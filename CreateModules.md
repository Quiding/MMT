# Creating MMT modules

This guide shows how to write your own module for MMT: how to hook into the team
management (members, roles, leader, names) and how to use the team communication.
Two complete examples are at the end.

The same guide, with copyable code, is in the game under `/mmt` > Help.

## What a module is

A module is its own addon in `Interface/AddOns`, next to the `MMT` folder, named
`MMT_<Name>`. It shows up in the game's AddOns list and under MODULES in `/mmt`, where
it can be switched on and off. Every client of your team runs its own copy, so
install the module on every account.

A new module folder only shows up after a full game restart (a `/reload` isn't enough).

## The two files

`MMT_Example/MMT_Example.toc`:

```
## Interface: 16001
## Title: MMT - Example
## Notes: One line about the module.
## Version: 1.0.0
## Author: YourName
## X-Repository: https://github.com/you/your-repo
## Dependencies: MMT
## DefaultState: disabled
## X-MMT-DefaultState: disabled
## X-MMT-Module: 1
## X-MMT-Title: Example

Module.lua
```

- `## Dependencies: MMT` makes sure the core loads first.
- `## X-MMT-Module: 1` marks the addon as an MMT module.
- `## DefaultState: disabled` and `## X-MMT-DefaultState: disabled`: the module starts
  switched off. Leave both lines out for a module that is on by default. MMT reads the
  second line when a profile reset switches the modules back to their defaults.
- `## Version`, `## Author` and `## X-Repository` are shown in `/mmt` > Modules.
- Don't list a `Bindings.xml` in the TOC: the game loads it on its own.

`MMT_Example/Module.lua`:

```lua
local MMT = MMT
local M = MMT.NewModule({
    name = "Example",                 -- unique; also the settings key
    title = "Example",
    description = "One line for the Modules page.",
    defaults = { greeting = true },   -- per profile, read/write M.db
    sync = true,                      -- optional: "Sync to team" button
    syncExclude = { "point" },        -- optional: keys that stay per client
})

M.OnEnable = function(self) end   -- switched on (also at login)
M.OnDisable = function(self) end  -- switched off: hide frames, stop timers
```

## Key bindings

MMT has its own group in the game's key binding menu (Esc > Options > Keybindings >
"MMT (Manage My Team)"). Every addon in it has its own header: "Core", "Item Compare",
"Item Bar", "Statistics", ... Put your module's keys there too:

1. Add a `Bindings.xml` to the module folder. Don't list it in the TOC: the game loads it
   on its own.
2. Give every binding `category="BINDING_CATEGORY_MMT"` (the core sets its title).
3. Give the first binding a header of your own, `MMT_<NAME>`. A header name may exist only
   once in the game, so never use `header="MMT"` (that one belongs to the core).
4. Set the texts in Lua: `BINDING_HEADER_MMT_<NAME>` for the header and
   `BINDING_NAME_<binding name>` for each key.

`MMT_Example/Bindings.xml`:

```xml
<Bindings>
    <Binding name="MMT_EXAMPLE_HELLO" header="MMT_EXAMPLE" category="BINDING_CATEGORY_MMT">
        MMT_ExampleHello()
    </Binding>
    <!-- a key that clicks a secure button (needed to use items or cast spells) -->
    <Binding name="CLICK MMTExampleButton:LeftButton" category="BINDING_CATEGORY_MMT"/>
</Bindings>
```

In `Module.lua`:

```lua
BINDING_HEADER_MMT_EXAMPLE = "Example"
BINDING_NAME_MMT_EXAMPLE_HELLO = "Say hello to the team"
_G["BINDING_NAME_CLICK MMTExampleButton:LeftButton"] = "Example button"

function MMT_ExampleHello()   -- global: the binding calls it
    if M.enabled then MMT.SendToTeam("EXHELLO", true) end
end
```

With `runOnUp="true"` the function also runs when the key is released and gets
`keystate` ("down" or "up"), e.g. for "hold to show" keys: see `MMT_ItemCompare`.

A new or changed `Bindings.xml` is only read at a full game restart.

## Module API

| Field or function | What it is |
| --- | --- |
| `M.db` | The module's settings in the active profile, defaults merged in |
| `M.store` | Account-wide data, kept across profiles, never synced |
| `M.enabled` | `true` while the module is on |
| `M:On(event, fn)` | A game event; runs only while the module is on |
| `M:Listen(callback, fn)` | A core callback (list below); only while on |
| `M:Heartbeat(key, fn)` | Adds `key=value` to the team heartbeat |
| `M:Debug(fmt, ...)` | A line in the debug log (`/mmt debug`) |
| `M.OnEnable`, `M.OnDisable` | Switched on / off |
| `M.OnProfileChanged` | Another profile became active |
| `M.Page(m, page)` | Optional settings page under MODULES |
| `M.Report(m, add)` | Optional lines for `/mmt debug dump` |
| `M.OnSyncReceived(m, from)` | After team settings arrived (with `sync = true`) |
| `M:SyncToTeam()`, `M:SyncButton(frame)` | Send the settings, or add the button to a frame of your own |

With `sync = true`, the core adds a "Sync to team" button to `M.Page` and the command
`/mmt sync <name>`. Only `M.db` is sent, never `M.store`.

## Hooking into the team management

### Team members

Every character is addressed by its **team key**, `"First-Last"`. Use it for
everything internal: tables, messages, lookups.

| Function | Returns |
| --- | --- |
| `MMT.SortedMembers()` | Team keys in team order |
| `MMT.db.team[key]` | `first`, `last`, `class`, `order`, `roles` of a member |
| `MMT.PlayerFull()` | This character's team key |
| `MMT.IsSelf(key)` | `true` for this character |
| `MMT.IsOnline(key)` | `true` while the member's MMT reports in |
| `MMT.Resolve(name)` | Team key for a typed or game name, or `nil` |
| `MMT.status[key]` | What the core already shares (see below) |
| `MMT.UpdateOwnStatus()` | This character's status, read fresh |

`MMT.status[key]` holds `level`, `cur`, `max`, `rested`, `class`, `isMax`, `layer`,
`layerKey`, `money`, `free` (free bag slots), `slots`, `durAvg`, `durMin`, `online` and
`sender`.

### Names and privacy

The player chooses how characters are shown (Team > Privacy: first name by default,
last name, full name, "Druid 1" or "Slot 2"). Follow that everywhere the player can
see a name:

- **Shown to the player** (frames, chat lines, tooltips, warnings): `MMT.ShownName(key)`.
- **Needed by the game** (macros, `/target`, invites, whispers):
  `MMT.RealName(key)`, `MMT.RealFirst(key)`, `MMT.RealLast(key)`.
- **Mouseover with the member's details:** `MMT.HoverMember(frame, function() return key end)`.

### Roles

Roles are lists of items and rules (exact item, item group, item class, quality, Bind on
Equip) that members are assigned to.

| Function | Returns |
| --- | --- |
| `MMT.MemberRoleList(key)` | The member's role names, sorted |
| `MMT.RoleWantsItem(role, item)` | `wants`, and how specific the matching rule is (item 4, group 3, class 2, quality / BoE 1) |
| `MMT.MembersForItem(item)` | Team keys whose roles want the item (most specific rule first, then team order), and the matching role per key |

`item` is an item link or an item ID.

### The leader

| Function | Returns |
| --- | --- |
| `MMT.FTLLeader()` | Team key of the FTL leader (the character you play), or `nil` |
| `MMT.IsNoticeLeaderHere()` | `true` on the client that should show notes: the FTL leader, else the group leader |
| `MMT.AlertAllowed(kind, key)` | `false` if the same alert for the same member came less than 5 seconds ago |

### XP window pieces

A row of the XP window shows pieces besides the name and the bar (gold, bags,
level, XP %, ...). Players switch them on or off, put them left of the bar or on
it, and drag them into their order (XP Window page, or `/mmt xp arrange`). A
module can add its own piece:

```lua
MMT.RegisterXPPiece{
    id = "example",              -- unique, kept in the player's order
    title = "Example",           -- name in the settings list
    side = "RIGHT",              -- "LEFT" of the bar or "RIGHT" on it (default RIGHT)
    on = false,                  -- shown until the player switches it (default off)
    sample = "42",               -- shown while arranging when text() has nothing
    tip = "One line for the settings list.",
    text = function(key, status) -- key: team key, status: MMT.status[key]
        if not M.enabled then return nil end
        return tostring(status.level)   -- nil or "" = nothing to show
    end,
}
```

`text` runs on every redraw of the window: keep it cheap. `MMT.UpdateXPWindow()`
redraws it when your value changed.

### Core callbacks (`M:Listen`)

| Callback | Arguments | When |
| --- | --- | --- |
| `TEAM_MESSAGE` | `key, sender, text, scope` | A team message the core doesn't handle itself |
| `XP_RECEIVED` | `key, sender, status` | A member's heartbeat arrived |
| `MEMBER_ONLINE` | `key, sender` | A member came online |
| `STATUS_CHANGED` | | Status of any member changed (redraw) |
| `TEAM_CHANGED` | | Members added, removed or reordered |
| `ROLES_CHANGED` | | Roles or their members changed |
| `FTL_LEADER` | `key` | The FTL leader changed |
| `PROFILE_CHANGED` | | Another profile became active |
| `LOGIN` | | MMT is ready after login |

## The team communication

Every client runs its own MMT. All messages go through one send queue in the core.
It keeps to the game's limits (about 10 messages per prefix, then 1 per second, on
group and guild channels) and sends throttled messages again. Only messages from
characters in this client's team are passed on to modules.

### Sending

```lua
-- the whole team (true = only members that are online), with a priority:
-- "ALERT" (first) | "NORMAL" (default) | "BULK" (last)
MMT.SendToTeam("EXPING:" .. GetMoney(), true, "ALERT")

-- one character, e.g. answer the sender of a message
MMT.SendAddon("EXPONG:ok", "WHISPER", sender)

-- a long text of any size: sent in parts, arrives in one piece
MMT.SendLong("EXDATA:" .. MMT.Serialize(myTable))

-- only the FTL leader; returns "self" (and sends nothing) on the leader
if MMT.SendToLeader("EXCOME:" .. GetZoneText()) == "self" then
    -- this character leads
end

-- the leader first (whispered), then everybody else: for urgent alerts
MMT.SendAlert("EXHELP")

-- everybody but the leader: scope as 5th argument of SendToTeam
MMT.SendToTeam("EXWAIT", true, "NORMAL", nil, "FOLLOWERS")
```

### Receiving

```lua
--   key    team key of the sender ("First-Last")
--   sender name as the game reported it (use it to whisper back)
--   scope  nil, "LEADER" or "FOLLOWERS"; messages not meant for this
--          client never arrive
M:Listen("TEAM_MESSAGE", function(key, sender, text, scope)
    local money = text:match("^EXPING:(%d+)$")
    if money then
        MMT.Print("%s has %s", MMT.ShownName(key), MMT.FormatMoney(tonumber(money)))
    end
end)
```

### The heartbeat

Small values can ride on the heartbeat, which every client sends every 30 seconds and
on changes, so they cost no extra messages. Values must not contain `:`, `,` or `=`.

```lua
M:Heartbeat("ex", function() return UnitLevel("player") end)
M:Listen("XP_RECEIVED", function(key, sender, status)
    local value = status.ext.ex   -- a string, or nil
end)
```

### Rules

- **Your own tag:** start every message with a tag of your own, e.g. `EXPING:`. These
  tags are taken by MMT: XP, XP2, BYE, PING, PONG, SYNC, SYNCHI, SYNCACK, EQREQ, EQD,
  EQS, QNQ, QNA, LH, LHGO, LHC, QTREQ, QTS, QTD, QTAB, FOL, CC, TAXI, NOTE, MOUNT,
  DISMOUNT, DEATH, RELEASE, REVIVE, IBS, IBA, IBU, IBC, RMQ, RMA, MPT, FTL, FTLM, SHC,
  SHQ, STA, STQ, and the prefixes `@L:` and `@F:`.
- **Size:** keep single messages under 250 bytes; use `MMT.SendLong` for more.
- **Team keys in messages, shown names on screen:** send keys, convert with
  `MMT.ShownName(key)` only when you display them.
- **Combat:** in combat many unit values are secret in this client and can't be
  compared. Wrap risky calls in `MMT.Safe(fn, ...)`, and don't change secure frames
  (action buttons, macros) in combat.
- **Combat log:** `COMBAT_LOG_EVENT_UNFILTERED` is reserved for the Blizzard UI on this
  client; registering it gets MMT blocked ("only available to the Blizzard UI").
  `M:On` skips it.

## Example 1: Team ready check

`/exready` on any character asks the team. Every member answers its free bag slots and
lowest durability, and the asking client prints one line per member.

```lua
-- MMT_ReadyCheck/Module.lua
local MMT = MMT
local M = MMT.NewModule({
    name = "ReadyCheck",
    title = "Ready Check",
    description = "Asks the team for free bag slots and durability.",
    defaults = { minFree = 4 },
})

-- our own answer
local function Answer()
    local s = MMT.UpdateOwnStatus()   -- fresh values of this character
    return ("RCA:%d:%d"):format(s.free or 0, s.durMin or 100)
end

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if text == "RCQ" then
        MMT.SendAddon(Answer(), "WHISPER", sender)   -- reply to the asker only
        return
    end
    local free, dur = text:match("^RCA:(%d+):(%d+)$")
    if free then
        free, dur = tonumber(free), tonumber(dur)
        local ok = free >= M.db.minFree and dur > 20
        MMT.Print("%s%s|r: %d free bag slots, durability %d%%",
            ok and "|cff66ff66" or "|cffff6666", MMT.ShownName(key), free, dur)
    end
end)

SLASH_MMTREADY1 = "/exready"
SlashCmdList.MMTREADY = function()
    if not M.enabled then return end
    MMT.SendToTeam("RCQ", true, "ALERT")
end

M.Page = function(self, page)
    local col = MMT.UI.Column(page, 0, 0, MMT.ConfigHelpers.COL_W)
    col:Header("Ready Check")
    col:Slider("Free bag slots needed", 0, 16, 1,
        function() return M.db.minFree end,
        function(v) M.db.minFree = v end)
    col:Note("Type /exready on any character.")
end
```

## Example 2: Where is everybody's hearthstone?

Each client puts its hearthstone location on the heartbeat. `/exhearth` lists the
team. The FTL leader also gets a chat note when a member's location changes.

```lua
-- MMT_Hearth/Module.lua
local MMT = MMT
local M = MMT.NewModule({
    name = "Hearth",
    title = "Hearth",
    description = "Shows where every team member's hearthstone is set.",
    defaults = {},
})

-- heartbeat values must not contain ":" "," or "="
local function Clean(s) return ((s or ""):gsub("[:,=]", " ")) end

M:Heartbeat("hs", function() return Clean(GetBindLocation()) end)

local known = {}   -- [team key] = location
M:Listen("XP_RECEIVED", function(key, sender, status)
    local hs = status.ext and status.ext.hs
    if not hs or hs == known[key] then return end
    if known[key] and MMT.IsNoticeLeaderHere() then
        MMT.Print("%s's hearthstone is now set to %s.", MMT.ShownName(key), hs)
    end
    known[key] = hs
end)

SLASH_MMTHEARTH1 = "/exhearth"
SlashCmdList.MMTHEARTH = function()
    if not M.enabled then return end
    for _, key in ipairs(MMT.SortedMembers()) do
        local hs = MMT.IsSelf(key) and Clean(GetBindLocation()) or known[key]
        MMT.Print("%s: %s", MMT.ShownName(key), hs or "unknown (offline?)")
    end
end

M.Report = function(self, add)
    for key, hs in pairs(known) do add(("Hearth %s: %s"):format(key, hs)) end
end
```

## More

- Larger working modules in this repository: `MMT_ItemBar` (sync of a shared bar,
  secure buttons, key bindings), `MMT_ItemCompare` (data in parts with a hash on the
  heartbeat), `MMT_QuestTracker` (snapshots and changes), `MMT_LootDistribution`
  (asking the team and waiting for answers).
- Debugging: `/mmt debug`, then `/mmt debug dump` for a report that includes your
  `M.Report` lines.
