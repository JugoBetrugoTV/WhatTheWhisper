# WhatTheWhisper against WIM

Compared against WIM master `7b0a585` (2026-09-08), which is the implementation
with the deferred queue and chat-line reconstruction, not the older revision that
simply ignored withheld chat events.

WIM is a compatibility reference. Where it has solved a client problem we had not
met yet, we take the *problem*, not the source.

## Restricted content (arenas, rated battlegrounds)

| | WIM | WhatTheWhisper |
|---|---|---|
| Detecting a withheld value | `issecretvalue` / `hasanysecretvalues` | same, behind `Compat` |
| Detecting the restriction | `C_ChatInfo.InChatMessagingLockdown` | same |
| Withheld message | deferred by chat line id, replayed | same |
| Recovering it | `C_ChatInfo.GetChatLine{Text,SenderName,SenderGUID}` | same |
| What is checked | `HasAnySecretValues(...)` over the whole payload | only the fields the event cannot do without |
| A line that never recovers | removed, queue continues | bounded retry, then that entry only is dropped |
| Battle.net identity | `GetBNGetGameAccountInfoByKName` on replay only | on every path, live and replayed |
| Original timestamp | carried as arg 29 | carried, and the message is stored with it |

Where we are ahead: a Battle.net account id or a sender GUID withheld on its own
does not delay a message whose text is perfectly readable, and the Battle.net
identity is recovered on the live path too rather than only after a replay.

Where WIM was ahead until this round: nothing outstanding.

## Feature audit

| WIM module | Ours | Verdict |
|---|---|---|
| WhisperEngine | ChatEvents + ConversationManager | ours: one thread per player, drafts, delivery state |
| ChatEngine (guild/party/raid windows) | — | rejected: this is a whisper messenger, and the game's chat frame is already good at channels |
| History | History + virtualized list | ours: retention policy, pruning, virtualization |
| Filters (pattern allow/ignore/block) | mute per conversation | rejected for now, see below |
| URLHandler | URLs | equivalent |
| TabManagement | Tabs + sweep | equivalent |
| OffScreenTracker (a marker to click) | `W.ClampToScreen` on restore | ours: nothing to find first |
| AddonCompartment | Minimap compartment entry | adopted, with the unread count |
| Sounds | Sounds | ours: per-context muting |
| Expose | Expose | equivalent |
| Alias | conversation nicknames | adopted |
| ShortcutBar | — | rejected: a toolbar of emotes is not what a messenger is short of |
| ClickControl (rebinding chat-name clicks) | — | rejected: retargeting other addons' click handlers is exactly the taint surface we avoid |
| Menu | ContextMenu | equivalent |
| StateHandler (per-state window rules) | Combat module | partly ours; see below |
| `FlashClientIcon` | on every whisper | adopted, behind a setting and behind Compat |
| `whisperMode` check | popup on first run | adopted as a settings row, no popup |

### Rejected, with reasons

**Pattern filters.** WIM's filter list is mostly an anti-gold-spam tool from an
era when the game had no answer. The game now has one, and duplicating an ignore
list a player has to maintain twice makes their life worse, not better. Our mute
covers the "not this conversation" case. Revisit if players actually ask.

**Channel windows.** WIM puts guild, party, raid and custom channels in windows
too. That is a different product. The chat frame is genuinely good at channels
and bad at whispers, and the whole premise here is to fix the second.

**ClickControl.** Rebinding what happens when you click a name elsewhere in the
UI means reaching into frames other addons also reach into. That is where taint
comes from, and the payoff is a shortcut that a right-click menu already gives.

### Partly adopted: per-state behaviour

WIM has separate rules for combat, PvP, arena, party, raid, resting and "other".
We have a combat module and per-context sound muting, which covers most of the
value. The remaining gap is per-context *window* behaviour. The reason to be
careful is that WIM's version is seven contexts multiplied by five behaviours,
which is thirty-five settings nobody reads. A sane version of this is a small
number of choices with good defaults; it is not done yet, and is the one item on
this list still worth building.
