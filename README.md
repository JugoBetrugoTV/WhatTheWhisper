# WhatTheWhisper

A messenger for World of Warcraft whispers. Every player you talk to gets their
own thread, with history, search, notifications, detachable windows and a look
that is built rather than borrowed from Blizzard's frame art.

Runs on **Retail 12.1.0**, **WoW Forever 1.60.1**, **MoP Classic 5.5.4**,
**TBC Anniversary 2.5.6** and **Classic Era 1.15.9** — the same feature set and
the same design on all five.

---

## Install

Copy the `WhatTheWhisper` folder into your AddOns directory. That is the whole
installation — there is nothing else to download.

```
Interface/AddOns/
    WhatTheWhisper/
        WhatTheWhisper_Mainline.toc   <- Retail
        WhatTheWhisper_Camelot.toc    <- Forever
        WhatTheWhisper_Mists.toc      <- MoP Classic
        WhatTheWhisper_TBC.toc        <- TBC Anniversary
        WhatTheWhisper_Vanilla.toc    <- Classic Era
        Libs/             <- LibStub and the five Ace3 libraries it uses
        Core/  Modules/  UI/  Skins/  Art/  Media/
```

One manifest per client, and the client picks its own — the folder is the same
on all of them, so there is nothing to choose at install time. All five load the
same file list; only the interface number differs.

`/wtw` opens the messenger. `/wtw help` lists the rest.

### Libraries

The addon embeds LibStub, CallbackHandler-1.0, AceAddon-3.0, AceConsole-3.0,
AceEvent-3.0, AceDB-3.0 and AceLocale-3.0 — the seven it actually uses, and no
more. They are byte-for-byte upstream and are never patched: `Libs.manifest.json`
records a hash for each, and the test suite fails if any of them changes.

That matters because these libraries are shared. If another addon has already
loaded a newer revision, LibStub keeps theirs and ours stands down; if ours is
newer, it upgrades theirs in place and their existing references keep working.
Nothing is forked into a private `WTWAceDB`-style namespace, because that would
give up exactly the sharing the mechanism exists for. `Tools/test/libs.lua`
plays out those collisions — older copy first, newer copy first, the same copy
loaded three times — and checks that no registration, callback or module is lost.

LibSharedMedia-3.0 is *not* embedded. It is asked for with the silent flag and
used only if some other addon provides it, so it is an integration rather than a
dependency.

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

**Windows.** Sidebar, tabs or both. Whether a whisper may open a window inside a
dungeon, raid or PvP is a setting of its own. Any conversation can be popped out into its
own window, and new whispers can open that way on their own, one small window per
person, the way WIM does it. Popouts snap to each other and to the main window.
Whether whispers also stay in the game's chat window is a setting: messenger only,
or messenger and chat. Exposé lays every open window out in a grid — by moving
the real windows, not by drawing fake previews.

**Replying.** The game's Reply key and `/r` answer whoever whispered last, in the
messenger, even when the whisper never reached the chat window. In the composer,
Up and Down bring back what you already said in that thread — a message that did
not arrive is one key away from being sent again — and Tab or Shift+Tab move to
the next or previous conversation. Shift-clicking an item, spell, quest or name in
the game puts its link in the box you are typing in, which is the messenger's own
composer and not only the game's chat box. A half-written message is still there
after a reload, and a button beside the emoji one holds up to ten quick replies —
starters in your language until you write your own — that go into the box, ready to
change, rather than straight out.

**Spam.** A list of words in the settings: a stranger's whisper containing one
is kept, silently — no sound, card, window or unread count, out of the chat
window too — at the bottom of the list, marked as filtered. Friends, guildmates,
Battle.net friends and anyone you have written to are never filtered, and "Not
spam" or "Mark as spam" in the menu overrule it either way.

**Hidden by the game's filter.** A whisper the game's language filter hid says so,
and one click on it shows it — on every client, since all of them ship the call.

**Notifications.** Toasts that summarise a chatty friend into one card instead of
a stack — in a corner or wherever you drag them, at the size you choose, with a
button that shows one to try the settings out. A configurable sound per event
with a per-conversation cooldown, a sound of its own for friends, guildmates and
Battle.net friends if you want one, an unread badge on the minimap button and in
the addon compartment, the same count on data-broker displays (Titan Panel,
ElvUI datatexts, Bazooka...) when one is installed, and Do-Not-Disturb with
per-instance-type muting.

**History.** Off, session-only, 1/7/30 days, or unlimited, with a message cap per
conversation and a conversation cap, pruned at login and logout. The settings
panel shows how many messages are stored and roughly what they cost on disk, so
nobody discovers a 40 MB Lua file the hard way. Three different things take
something away, and each says what it does: *Close conversation* shuts the tab,
*Clear history* empties the thread but keeps the row in the list, and *Delete
conversation* removes the thread itself with everything stored for it. Settings
› History has *Clear all history* (keeps the rows) and *Delete all
conversations* (does not).

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
- **Some player actions are Blizzard's alone.** Adding a friend and `/who` are
  restricted: called from an addon they are blocked with an
  `ADDON_ACTION_BLOCKED` warning, even from a click. "Add friend" therefore runs
  the client's own `/friend` from a real `SecureActionButton`; it is disabled in
  combat (attributes cannot be written then), and a combat state driver takes the
  button away if combat starts while the menu is open. "Look up" does not send a
  `/who` at all: it lists the player's public profile pages (Armory, Raider.IO,
  Warcraft Logs, WoWProgress, Check-PvP, Wowhead, Simple Armory on Retail; the
  Classic sites on the Classic clients) for copying.
- **Reporting is Blizzard's, from the click on.** An addon may not send a report
  (`C_ReportSystem.SendReport`: "Not allowed to be called by addons"), and one
  opened from addon code carries the addon's taint into everything it sets off.
  The game reports a whisper from a right click on the sender's name in its chat
  window — a name that is not there when whispers are shown in the messenger
  only. So "Report" puts it there: the chat window's own player link, carrying the
  whisper's chat line, whose right-click menu has Report on it. That works for
  whispers from this session (the line means nothing after a reload) and not for
  Battle.net, whose chat link carries no line to report.
- **The game learns who to reply to from its chat window.** A whisper shown in
  the messenger only never becomes the target of the Reply key, so the addon
  answers the key itself, in the messenger. It does not write the game's own reply
  list: a value an addon puts there makes the player's replies fail in arenas and
  rated battlegrounds, where the client withholds chat from addons. There, and for
  any whisper the chat window did show, Reply is the game's alone.
- **WoW Forever names have two parts** ("Matt Loc") and no realm suffix. The addon
  addresses everyone on your own realm, and everyone on Forever, by name alone,
  the way the client itself replies. `/friend` takes the second name as a note,
  so "Add friend" is not offered for a two-part name.
- **No "is this player online" query.** Online state is only known for friends,
  guildmates, group members and after a `/who` you typed yourself. Unknown state shows
  no dot at all rather than a grey one that implies something.
- **Level and faction** come from the same sources, plus the race in the chat
  event's GUID. Anything unknown is left out instead of guessed.
- **No emoji font.** None of these clients ship emoji glyphs, so the addon
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

The text is set in **Inter**, a typeface drawn for screens, which ships with the
addon in regular and semibold (`Media/Fonts`, SIL Open Font License, licence
beside the files). Names and titles are semibold, everything read at length is
regular. Korean and Chinese keep the client's own font, since Inter has no
glyphs for them, and Settings › Appearance › Font switches back to the game's
chat font for anyone who wants the window to match the rest of their UI.

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
Media/Fonts/           Inter, regular and semibold, and its licence
Media/Icons/           drop-in replacements for any glyph (docs/ICON-REPLACEMENT.md)
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
messages. It runs against seven client profiles with the API surface each one
actually has, so a Retail-only call fails the Classic run. Those surfaces are
read out of Blizzard's own generated API documentation at the tag for each
shipping build rather than assumed, because Classic receives APIs by backport
and guessing from "when Retail got it" has already been wrong once.

```sh
python3 Tools/gen_icons.py      # Art/Icons.tga  + UI/IconAtlas.lua
python3 Tools/gen_emoji.py      # Art/Emoji.tga  + UI/EmojiAtlas.lua
python3 Tools/gen_shapes.py     # Art/Round.tga, Shadow.tga, Logo.tga
python3 Tools/design_preview.py midnight sidebar
```

`design_preview.py` renders the main window from the addon's real tokens, read
out of the Lua source. It is a design review instrument: if the preview looks
wrong, the addon looks wrong.

```sh
python3 Tools/render/render.py main settings toast --skin midnight
```

`Tools/render` goes one step further: it loads the real addon into the mock
client, builds the scene (main, empty, menu, emoji, settings, toast, popout)
and paints every texture and string the addon created, in the client's draw
order, with text measured from the real font files. Nothing is laid out by the
renderer, so the picture is what the addon builds. It is how the search field's
magnifier was found hiding under the field's own background; `occlusion.lua`
now fails the build on that whole class of mistake.
