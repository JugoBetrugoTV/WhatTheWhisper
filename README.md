# WhatTheWhisper

A messenger for World of Warcraft whispers. Every player you talk to gets their
own thread, with history, search, notifications, detachable windows and a look
that is built rather than borrowed from Blizzard's frame art.

Runs on **Retail 12.1.0**, **MoP Classic 5.5.4**, **TBC Anniversary 2.5.6** and
**Classic Era 1.15.9** — the same feature set and the same design on all four.

---

## Install

```
Interface/AddOns/
    Ace3/                 <- the library folder already in this repository
    WhatTheWhisper/
```

`Ace3` is a hard dependency (`## Dependencies: Ace3`) and ships alongside the
addon. Nothing inside `Ace3/` is modified.

`/wtw` opens the messenger. `/wtw help` lists the rest.

---

## What it does

**Conversations.** One thread per player, kept as long as you ask it to be, with
its own scroll position, unread count, draft, mute and pin state. Battle.net
whispers get threads too, keyed by BattleTag so they survive a session.

**Messages.** Chat bubbles, left and right, grouped when the same person writes
several times in a row. Date separators, timestamps on hover, per-conversation
search that jumps to and highlights the match, and links that are found without
false-positiving on "3.5" or "e.g.".

**Delivery state that means something.** An outgoing message shows as pending,
then as sent when the server echoes it back, and as failed when the server
answers "No player named …". That is real information, not a spinner.

**Windows.** Sidebar, tabs or both. Any conversation can be popped out into its
own window; popouts snap to each other and to the main window. Exposé lays every
open window out in a grid — by moving the real windows, not by drawing fake
previews.

**Notifications.** Toasts that summarise a chatty friend into one card instead of
a stack, a configurable sound per event with a per-conversation cooldown, an
unread badge on the minimap button, and Do-Not-Disturb with per-instance-type
muting.

**History.** Off, session-only, 1/7/30 days, or unlimited, with a message cap per
conversation and a conversation cap, pruned at login and logout. The settings
panel shows how many messages are stored and roughly what they cost on disk, so
nobody discovers a 40 MB Lua file the hard way.

**Export.** Plain text, Markdown, BBCode or CSV, into a box that is already
focused and already selected.

---

## What WoW does not allow

Stated plainly, because the alternative is pretending:

- **No clipboard API.** Nothing can copy to the clipboard for you. Copy and
  export put the text in a focused, pre-selected EditBox so Ctrl+C is the only
  step left.
- **No opening a browser.** Links are detected, coloured and clickable, and
  clicking one opens that copy box. An addon cannot launch anything.
- **No targeting from insecure code.** The "Target" context-menu entry is backed
  by a real `SecureActionButton` running a `/target` macro. Attributes cannot be
  written during combat, so in combat the entry is disabled with an explanation
  rather than silently doing nothing.
- **No "is this player online" query.** Online state is only known for friends,
  guildmates, group members and after a `/who` you asked for. Unknown state shows
  no dot at all rather than a grey one that implies something.
- **Level and faction** come from the same sources, plus the race in the chat
  event's GUID. Anything unknown is left out instead of guessed.
- **No emoji font.** None of the four clients ship emoji glyphs, so the addon
  carries its own atlas and renders it through inline texture markup. What goes
  over the wire is always plain text (`:)`, `:fire:`, `{rt1}`), so the person on
  the other end sees something sensible with or without this addon.
- **255 bytes per whisper.** Longer input is split on word boundaries without
  cutting a UTF-8 sequence or an item link, and the composer says how many
  messages it will become before you press Enter.

---

## Design

`WhatTheWhisper/DESIGN.md` is the design system this UI is built against:
spacing scale, type scale, colour roles, per-component specs, motion, and the
per-client parity table. Every number in it exists as a named constant in
`Core/Namespace.lua`; nothing else is allowed to invent a spacing or a size.

Six skins ship, each a complete token set rather than a background colour:
Midnight, Messenger, Dark, Minimal, Glass and Classic. A skin that omits a role
inherits it from Midnight, so a partial skin cannot render broken.

The chrome is drawn, not borrowed. Rounded rectangles are assembled from a
generated disc texture (four corner quads sampling one quadrant, plus three
bands), hairlines are snapped to physical pixels, and the icon and emoji atlases
are generated from `Tools/gen_*.py`. That is why Classic Era looks the same as
Retail instead of degrading to a grey box.

---

## Layout

```
Core/
  Namespace.lua        design tokens and shared constants
  Compat/              one probe-based layer + a file per flavour
  Util/                UTF-8 text, colour, pooling, pixel snapping, event bus
  Defaults.lua         SavedVariables shape
  Options.lua          declarative settings schema
  Core.lua             AceAddon lifecycle, slash commands, bindings
Modules/               conversation model, history, chat events, player info,
                       sounds, notifications, links, emoticons, export,
                       combat, search
UI/                    theme, drawing primitives, motion, widget toolkit,
                       and the views built from them
Skins/                 six complete token sets
Art/                   generated .tga atlases and geometry
```

Rule for the rest of the codebase: never call a `C_*` namespace or a
version-specific global directly, always go through `ns.Compat`.

---

## Development

```sh
sh Tools/test/all.sh
```

runs syntax checks, luacheck, atlas and locale consistency, and then loads the
addon into a WoW API mock and drives it: login, chat traffic, sending, delivery
reconciliation, every skin, every option permutation, popouts, Exposé, combat
and logout — with an assertion that virtualisation still holds at 2 000
messages. It runs against four client profiles with the API surface each one
actually has, so a Retail-only call fails the Classic run.

```sh
python3 Tools/gen_icons.py      # Art/Icons.tga  + UI/IconAtlas.lua
python3 Tools/gen_emoji.py      # Art/Emoji.tga  + UI/EmojiAtlas.lua
python3 Tools/gen_shapes.py     # Art/Round.tga, Shadow.tga, Logo.tga
python3 Tools/design_preview.py midnight sidebar
```

`design_preview.py` renders the main window from the addon's real tokens, read
out of the Lua source. It is a design review instrument: if the preview looks
wrong, the addon looks wrong.
