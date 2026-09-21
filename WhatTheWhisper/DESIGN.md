# WhatTheWhisper — Design System

> A messenger that happens to live inside World of Warcraft.
> Target quality bar: Apple Messages on an iPad — not "WoW addon".
>
> Midnight is iOS Dark and is the skin the design is drawn for. The other five keep
> working and take the same shapes; they are not what this document describes.

This document is the **contract** between design and code. Every number in here exists as a
named constant in `Core/Namespace.lua` (`ns.S`, `ns.SZ`, `ns.T`, `ns.R`, `ns.MOTION`).
No magic numbers are allowed anywhere else in the codebase.

---

## 0. Design principles

1. **Calm surfaces, loud content.** Chrome is near-monochrome; colour is reserved for the
   accent (selection, unread, own messages) and class colours. Nothing else is coloured.
2. **Hierarchy through value, not weight.** WoW ships no bold font cut. Emphasis is created
   with *brightness* and *size*, never with fake outlines or shadows on text.
3. **One radius family, one spacing family.** Spacing 4 / 8 / 12 / 16 / 20 / 24 / 32;
   radius 8 / 12 / 16 / 22 (Apple's corner ladder) plus a pill. Nothing else.
4. **Every interactive element has five states**: rest, hover, pressed, selected, disabled.
   A control without a hover state is an unfinished control.
5. **Motion is feedback, never decoration.** 100–260 ms, ease-out. Nothing loops forever.
6. **Identical on every client.** No feature or visual may exist on Retail only.

---

## 1. Layout

### 1.1 Main window

```
┌──────────────────────────────────────────────────────────────────────┐
│ ●  WhatTheWhisper                            [⌗] [≡] [–] [✕]         │ 34  Titlebar
├───────────────────────────┬──────────────────────────────────────────┤
│  ⌕  Search           [+]  │  Thrall │ Jaina │ Sylvanas               │ 36  Tabs
├───────────────────────────┼──────────────────────────────────────────┤
│ ╭─────────────────────╮   │  ◗ Thrall                     [⌕][⧉][⋯]  │ 64  Header
│ │ ◗ Thrall      22:41 │   ├──────────────────────────────────────────┤
│ │   Yo kommst du?  ②  │   │                Today 22:41               │
│ ╰─────────────────────╯   │                                          │
│   ──────────────────────  │  ◗ ╭──────────────────────╮              │
│   ◗ Jaina          21:07  │    │ Yo kommst du Raid?   │              │
│     Portal in 5           │    ╰──────────────────────╯              │
│   ──────────────────────  │                    ╭───────────────────╮ │
│   ◗ Sylvanas         Mon  │                    │ Ja bin gleich da  │ │
│     ok bin da             │                    ╰───────────────────╯ │
│                           │                            ✓✓ Delivered  │
│                           ├──────────────────────────────────────────┤
│                           │ ☺ │ Message Thrall…             ( ↑ ) │  │ 66  Composer
└───────────────────────────┴──────────────────────────────────────────┘
   320 sidebar
```

Two columns, the way Messages is built on an iPad: the conversation is the deepest
surface and everything else sits above it. The selected row in the sidebar is an inset
rounded card, not a bar in the gutter; the time in the thread is a centred marker, not
something tucked into a bubble; the send arrow lives inside the composer's field.

Layer stack (back → front), each layer differs by **brightness only**:

| Layer          | Role                                   |
|----------------|----------------------------------------|
| `bg0`          | window base / titlebar                 |
| `bg1`          | sidebar column                         |
| `bg2`          | conversation surface (message canvas)  |
| `bg3`          | raised: cards, menus, tooltips, popouts, toasts |
| `inputBg`      | a field: the composer, search, settings inputs |
| `trackBg`      | derived — the groove of a slider, switch or segmented control |
| `thumbBg`      | derived — the raised thumb running in that groove |
| `hover`        | +6 % white over the owning layer       |
| `selected`     | +13 % white over the owning layer      |
| `scrim`        | 60 % black, full screen (Exposé/modal) |

`trackBg` and `thumbBg` are derived in `Theme.lua` rather than written into six skin
files: the groove is `bg3` mixed towards the text colour, and the thumb is the groove
lightened until it clears it by a fixed luminance. A skin cannot forget to define them,
and neither can be a colour that makes the control invisible.

Separation between columns is a **1 physical-pixel hairline** at `borderSubtle`, never a
3-D bevel, never a Blizzard backdrop edge.

### 1.2 Metrics

Every row below is checked against `Core/Namespace.lua` by `Tools/test/check_structure.py`.
A number here that the code does not have fails the build.

| Constant                 | px   | Notes |
|--------------------------|------|-------|
| `WINDOW_W`               | 1040 | default |
| `WINDOW_H`               | 640  | default |
| `WINDOW_MIN_W`           | 700  | hard floor |
| `WINDOW_MIN_H`           | 440  | hard floor |
| `TITLEBAR_H`             | 34   | |
| `SIDEBAR_W`              | 320  | user resizable, see below |
| `SIDEBAR_MIN_W`          | 240  | |
| `SIDEBAR_MAX_W`          | 440  | |
| `SIDEBAR_COMPACT_AT`     | 248  | below → icon rail |
| `SIDEBAR_RAIL_W`         | 76   | the rail itself |
| `SIDEBAR_HEADER_H`       | 60   | |
| `SEARCH_H`               | 36   | the iOS search field |
| `ROW_H`                  | 76   | a 48 avatar with 14 above and below |
| `ROW_H_COMPACT`          | 60   | |
| `HEADER_H`               | 64   | |
| `TAB_H`                  | 36   | |
| `TAB_MARKER_H`           | 3    | along the active tab's top edge |
| `COMPOSER_MIN_H`         | 66   | |
| `COMPOSER_MAX_H`         | 160  | the field stops growing here |
| `COMPOSER_FIELD_H`       | 42   | one line of 17px body |
| `AVATAR_LG`              | 48   | sidebar row |
| `AVATAR_MD`              | 40   | header, toast |
| `AVATAR_SM`              | 28   | thread |
| `AVATAR_XS`              | 20   | inline |
| `BADGE_H`                | 20   | pill, min width 20 |
| `ICON_BTN`               | 32   | 22px glyph centred |
| `ICON_BTN_SM`            | 28   | title bars and search rows |
| `SEND_BTN`               | 36   | circular, inside the field |
| `TOGGLE_W`               | 51   | the iOS switch, exactly |
| `TOGGLE_H`               | 31   | |
| `TOGGLE_KNOB`            | 27   | |
| `SEGMENT_H`              | 32   | |
| `SEGMENT_RIM`            | 2    | thumb inset from the track |
| `MENU_ITEM_H`            | 44   | |
| `MENU_ICON`              | 20   | trailing, see §4.9 |
| `SETTINGS_ROW_H`         | 44   | the iOS table row |
| `SCROLLBAR_W`            | 4    | auto-hide |
| `SCROLLBAR_HIT`          | 10   | |
| `LIST_PAD_X`             | 24   | |
| `LIST_PAD_Y`             | 20   | |
| `BUBBLE_PAD_X`           | 12   | |
| `BUBBLE_PAD_Y`           | 8    | |
| `BUBBLE_MAX_ABS`         | 620  | |
| `MSG_GAP_TIGHT`          | 3    | within a group |
| `MSG_GAP_GROUP`          | 14   | between groups |
| `MSG_GAP_DATE`           | 24   | above a time marker |
| `SEP_WORD_GAP`           | 4    | between the day and the clock |
| `RECEIPT_GAP`            | 3    | between the last bubble and its delivery line |
| `RECEIPT_ICON_GAP`       | 4    | between the mark and the word |
| `STATUS_ICON`            | 16   | the delivery mark |
| `TOAST_W`                | 332  | |
| `TOAST_H`                | 68   | |
| `SETTINGS_W`             | 900  | |
| `SETTINGS_H`             | 640  | |
| `SETTINGS_NAV_W`         | 216  | at the default font; scales with the type ramp |

### 1.3 Responsive rules

| Width                        | Behaviour |
|------------------------------|-----------|
| `< SIDEBAR_COMPACT_AT`       | avatar-only rail; name/preview/time hidden, badge overlays avatar |
| `< 760` window               | sidebar auto-narrows before the conversation gives up space |
| `< WINDOW_MIN_W`             | blocked by min size |
| any                          | bubbles cap at `min(68 % of canvas, BUBBLE_MAX_ABS)` so ultrawide never stretches text |

Everything is laid out with anchors + explicit sizes, and every hairline is snapped to a
physical pixel (`ns.Pixel`), so 1080p / 1440p / 4K and UI-scale 0.53–1.0 all render crisp.
Widths that hold words -- the settings control column, the settings navigation column --
are multiplied by the type ramp, because a column sized once fits the default font size
and truncates at every step above it.

---

## 2. Typography

Apple's text ramp, by the names Apple gives the steps, because using the real numbers
rather than numbers near them is most of the difference between "iOS-ish" and iOS. Font
path is derived from `ChatFontNormal` at runtime so every locale (incl. ruRU / koKR /
zhCN) gets a valid face; user-selectable faces are validated before use.

| Token       | px | iOS style  | Use |
|-------------|----|------------|-----|
| `T.micro`   | 11 | caption 2  | time markers, the delivery line, badge counts |
| `T.small`   | 13 | footnote   | descriptions, section headers, empty-state body |
| `T.subhead` | 15 | subheadline| last-message preview, control values, secondary rows |
| `T.body`    | 17 | body       | message text, list titles, settings labels, input |
| `T.title`   | 20 | title 3    | the name in a conversation header |
| `T.display` | 24 | title 2    | empty-state headline |

iOS separates a title from a body with *weight* as often as with size, and the game ships
no semibold face for most of the fonts a player can pick. Where Apple would set 17
semibold over 17 regular, this steps up a size instead — and where two strings share a
line and one should lead (the day and the clock in a time marker), the emphasis ladder
carries it instead of the weight.

* Line spacing for message bodies: **5 px** — iOS body is 17 over a 22 line box.
  Everything else: default.
* Nothing is smaller than 11. A timestamp that has to be squinted at is not quiet, it is
  unreadable, and those are different things.
* No `OUTLINE` flags anywhere in chrome (outlines are the #1 "2010 addon" tell). Optional
  outline exists only for the *message text* skin setting, off by default.
* Emphasis ladder: `textMuted` → `textSecondary` → `textPrimary` → `accent`.

---

## 3. Colour

Roles are skin-defined; the code never names a literal colour. Reference values below are
the default skin **Midnight**.

Midnight is iOS Dark: Apple's own system colours, by their own names and their own
values. Using the real numbers rather than numbers near them is most of the difference
between "iOS-ish" and iOS — these are the greys a player has been looking at on a phone
every day for years, and the eye notices when they are almost right.

| Role           | Midnight   | iOS name | Meaning |
|----------------|------------|----------|---------|
| `bg0`          | `#000000`  | systemBackground | base |
| `bg1`          | `#1C1C1E`  | systemGray6 | sidebar |
| `bg2`          | `#000000`  | systemBackground | the thread, the way Messages does it |
| `bg3`          | `#1C1C1E`  | systemGray6 | raised: cards, menus, toasts |
| `headerBg`     | `#1C1C1E`  | systemGray6 | navigation bar, tab strip, active tab |
| `composerBg`   | `#000000`  | systemBackground | the field floats on the conversation |
| `inputBg`      | `#2C2C2E`  | systemGray5 | a field |
| `hover`        | white 6 %  | | |
| `selected`     | white 13 % | | the inset card under the row you are in |
| `borderSubtle` | white 9 %  | | hairlines |
| `borderStrong` | white 16 % | | the composer's stroke, segment dividers |
| `accent`       | `#0A84FF`  | systemBlue (dark) | selection, unread, focus |
| `onAccent`     | `#FFFFFF`  | | |
| `textPrimary`  | `#FFFFFF`  | label | |
| `textSecondary`| `#EBEBF5` 60 % | secondary label | |
| `textMuted`    | `#EBEBF5` 40 % | | |
| `textDisabled` | `#EBEBF5` 25 % | tertiary label | |
| `bubbleIn`     | `#2C2C2E`  | systemGray5 | one step off the black thread |
| `bubbleOut`    | `#0A6FD8`  | | see below |
| `success`      | `#30D158`  | systemGreen | online dot |
| `danger`       | `#FF453A`  | systemRed | failed send, destructive menu items |
| `warning`      | `#FF9F0A`  | systemOrange | |

The label ramp is not four greys: it is one colour at four opacities, which is why
secondary text sits in the same family as primary instead of looking like a different
decision.

The outgoing bubble is the one deliberate departure. White on systemBlue measures
3.65:1, and message text is the thing in this addon most likely to be read at two in the
morning; `#0A6FD8` is the same blue at 4.91:1, and beside the send button nobody can tell
them apart.

Class colours are used **only** for: avatar ring/fill, contact name, bubble sender name —
and only when `appearance.classColors` is on. They never colour backgrounds.

---

## 4. Components

### 4.1 Conversation row (sidebar)

```
 ╭─────────────────────────────────────╮
 │  ╭──╮  Thrall                 22:41 │
 │  │◉ │  Yo kommst du Raid?        ②  │   ROW_H tall
 │  ╰──╯                               │
 ╰─────────────────────────────────────╯   selected: an inset rounded card
    ──────────────────────────────────     a hairline on the text column
```

* padding `S.lg` either side, avatar `AVATAR_LG`, gap `S.md`
* name `T.body` `textPrimary`; preview `T.subhead`; time `T.small`
* unread → the time takes the accent, the **preview** lifts `textMuted → textSecondary`
  and the badge appears. No bold fakery.
* muted conversation: name drops to `textSecondary`, mute glyph after the name, badge
  renders in `textMuted` instead of accent
* pinned: pin glyph before the timestamp; pinned rows sort above the rest
* hover: `hover` fill, 140 ms; **selected: an inset rounded card** at `R.md`, inset by
  `S.sm` either side — the way an iPad list marks its selection. There is no bar in the
  gutter: a marker beside the row is a desktop-app idiom, and the card is the iOS one.
* the hairline between two rows starts on the text column, not at the row's edge, and is
  not drawn under the selected row or the last one
* pressed: `selected` fill immediately (no animation) — clicks must feel instant

### 4.2 Avatar

Circular (mask), three sources with graceful fallback:
`portrait (unit in range) → class icon → class-coloured disc with UTF-8 initial`.
Optional 8 px status dot (bottom-right) with a 2 px cut-out ring in the owning layer colour.
If `CreateMaskTexture` is unavailable the avatar degrades to a rounded square — same size,
same palette, so layout never shifts.

### 4.3 Message bubble

* max width `min(68 %, 620)`, padding `12 / 8`, radius `R.lg`
* **a bubble holds its text and the padding around it, and nothing else.** No time in
  the corner, no tick tucked into the bottom right. Everything a message needs said
  about it is said outside it — §4.4 for when, §4.5 for whether it arrived. This is the
  difference between a conversation and a chat log, and it is the reason the thread
  reads the way it does.
* incoming: left, `bubbleIn`; outgoing: right, `bubbleOut`
* **Grouping**: same sender + same type + ≤ 300 s apart → one group. The corners facing
  the group's spine go square in the middle of a run and stay round at its ends, so a
  stack reads as one block with a rounded top and bottom. No drawn tail.
  First bubble of an incoming group carries the avatar; the rest are bare, 3 px apart.
* per-message timestamp on hover, outside the bubble on the outer side — the drag-left
  gesture's equivalent, and the only time in the thread when §4.4 is switched off
* a message the server refused keeps a `failed` mark at `STATUS_ICON`, outside the
  bubble on the inner side, for as long as it is in the thread
* selection/copy: right-click opens the per-message menu

### 4.4 Time marker

Centred, `T.micro`, one line, nothing drawn behind it: the day in `textSecondary`, the
clock in `textMuted`, `SEP_WORD_GAP` apart. `MSG_GAP_DATE` above, `S.md` below.

It is emitted once per resumption of the conversation, not once per message: on a new
day, or after the thread has been quiet for `STAMP_WINDOW` (an hour). What it can say
is what the two settings allow — *Show timestamps* contributes the clock, *Show date
separators* contributes `Today` / `Yesterday` / weekday / the date — and with neither
on, no marker is drawn at all.

Not a pill. A pill is a chip and a chip is something you can press; a rule with a word
in a gap is a document divider. This is a paragraph break in a conversation.

### 4.5 Delivery line

One line under the newest message you sent, right aligned to its edge, `RECEIPT_GAP`
below it: a `STATUS_ICON` mark and then the state in words — `Sending` (one check),
`Delivered` (two), `Not delivered` (in `danger`). Never on any other message: anything
further back was either answered, which is proof it arrived, or is itself the newest.

This is real delivery information. `Delivered` means the server echoed the whisper back;
`Not delivered` means it replied "no player named …". Nothing here is simulated.

### 4.6 Composer

An `inputBg` pill at `COMPOSER_FIELD_H`, stroked with a `borderStrong` hairline — the one
field in the addon drawn with a line around it, because the Messages composer is stroked
and it is the field the eye goes to first. It shares the thread's column: its right edge
lands on the outgoing bubbles' right edge.

The emoji button (`ICON_BTN`) sits outside the field on the left. The send arrow
(`SEND_BTN`) sits **inside** it on the right, in its corner, with the same gap beside it
as under it — that is how Messages arranges the two, and the arrow being inside is what
makes the field read as the thing you are working in rather than as one control in a row
of three. The field keeps that room clear: text, caret and placeholder all stop before the
arrow. The arrow fades from `textMuted` to `accent` the moment the field is non-empty.

Both buttons sit on the *last* line of the field, so once a message wraps they stay with
the line being typed. Focus lifts the field's fill rather than drawing a ring.
Placeholder: *"Message Thrall…"*. `Enter` sends, `Shift+Enter` newline, `Esc` blurs.
Multi-line input is split into whisper-legal chunks (255 **bytes**, UTF-8 safe, word-aware).
A character counter appears only at ≥ 200 bytes, in `textMuted`, `danger` past the limit.

### 4.7 Tabs

Browser-style, not Blizzard registers: `TAB_H` tall, radius `R.md` on the top corners
only, inactive on `bg1`, active on `headerBg` so it reads as continuous with the header
directly beneath the strip. In several skins those are the same colour, so the fill says
nothing at all there and a `TAB_MARKER_H` bar along the active tab's top edge carries the
selection instead. (It used to be `bg2` — the thread, which is nowhere near the strip; in
a palette where the thread is black and the header is not, that made the active tab a
black notch cut into a grey plate.) Unread → accent dot left of the label. Close button
appears on hover (or when active). Drag to reorder with a 150 ms slide of the displaced
neighbours.

### 4.8 Buttons

Five variants, one state machine, identical geometry. An icon button is `ICON_BTN` (or
`ICON_BTN_SM` in a title bar) with a **pill** hover wash under it: a square highlight
behind a toolbar icon is the shape every native toolbar stopped using a decade ago. A text
button is 32 tall by default at `R.md`.

| Variant     | Rest | Hover | Pressed | Disabled |
|-------------|------|-------|---------|----------|
| `ghost`     | transparent, `textSecondary` | `hover` fill, `textPrimary` | `pressed` fill | `textDisabled` |
| `primary`   | `accent` fill, `onAccent` | `accentHover` | `accentActive` | 40 % alpha |
| `danger`    | transparent, `danger` | `danger @ 16 %` fill | `danger @ 26 %` | `textDisabled` |
| `subtle`    | `bg3` fill, `textSecondary` | `hover` fill, `textPrimary` | `pressed` fill | 50 % alpha |
| `outline`   | `trackBg` edge, `textSecondary` | `hover` fill, `textPrimary` | `pressed` fill | `borderSubtle` edge |

`outline` exists for a button sitting on a raised surface, where a filled one would be the
same colour as the panel under it and simply disappear. Its edge uses `trackBg` rather
than a border role: the border roles are tuned to sit quietly on the window, and in
Minimal `borderStrong` against `bg3` comes out at 1.29:1 — under the point where an edge
is visible at all, which is the exact bug the variant exists to fix.

### 4.9 Context menu

Own implementation (no `UIDropDownMenu` → no taint, full design control).
`bg3`, radius `R.lg`, 1 px `borderSubtle`, a shadow, `S.sm` vertical padding, item height
`MENU_ITEM_H`, label `T.body`.

**The label leads and the mark trails**, at `MENU_ICON`, which is the way iOS and macOS
set a menu: you read what the entry does, and the icon is there to recognise it by once
you know. Icon-first is the Windows and Android arrangement and it turns every menu into a
column of symbols with words after them. The panel reserves the mark's column whether or
not an entry has one, so hiding an entry cannot change the menu's width.

Separator = 1 px hairline with `S.sm` margins. Destructive items are `danger` and always
sit last, below a separator. Opens with a 90 ms fade + 4 px rise; a full-screen invisible
catcher closes it on any outside click or `Esc`.

### 4.10 Tooltip

Own frame. `bg3`, radius 6, padding 8/5, `T.micro`, single line, 350 ms delay, 90 ms fade.
Never taller than two lines. Blizzard's `GameTooltip` is used **only** for real game
hyperlinks (items, spells, achievements) inside message text, where it is the correct tool.

### 4.11 Toast notification

Top-right stack (corner configurable), `TOAST_W` × `TOAST_H`, `bg3`, radius `R.xl` — an
iOS banner is the roundest thing the system draws outside a bubble — with a shadow and no
outline. `AVATAR_MD` + name `T.body` + time `T.micro` + one clamped preview line
`T.subhead`. Enters with a 16 px slide
from the edge + fade over 200 ms, auto-dismisses after 5 s with a hairline progress bar in
`accent`. Hover pauses the timer; click opens the conversation.

### 4.12 Scrolling

* Custom 4 px scrollbar (10 px hit area), `borderStrong`, radius 2. Hidden at rest, fades
  in on hover-over-list or during scroll, fades out 900 ms after the last movement.
* **Smart auto-scroll**: pinned to bottom → new messages scroll in. Scrolled up → the view
  does *not* move; instead a pill appears above the composer:
  `↓ 3 new messages`, `accent` fill, click → smooth scroll to bottom.
* Wheel scroll animates over 140 ms (`Reduced`/`Off` → instant).

### 4.13 Empty states

Centred, max 320 px wide, vertically at 42 % height (optically centred, not mathematically).

| Situation | Headline (`T.display`, `textSecondary`) | Body (`T.small`, `textMuted`) |
|-----------|------------------------------------------|-------------------------------|
| no conversations | No conversations yet | Whisper someone to start a conversation. |
| nothing selected | Pick a conversation | Your whispers stay here, per player. |
| search empty | No matches | Try a different name or word. |
| history empty | Start the conversation | Say hi to %s. |
| history disabled | History is off | Enable it in Settings › History to keep messages. |

Each carries a line-art glyph (`EMPTY_ICON` / `EMPTY_ICON_SM`) drawn from the same icon
primitives, at about a fifth alpha.

### 4.14 Settings

An iOS grouped list. Left nav `SETTINGS_NAV_W` (`bg1`, `SETTINGS_NAV_ROW_H` rows, the
active one an inset rounded card — no bar in the gutter, same as the sidebar), right
content on `bg2`, max content width `SETTINGS_MAX_CONTENT` centred.

Settings are grouped into **cards** (`bg3`, radius `R.lg`) with the section's name above
the card rather than inside it, `SETTINGS_ROW_H` rows separated by hairlines inset to the
label column, and a `T.small`/`textMuted` caption under a label that needs one. Label
`T.body`, control value `T.subhead`.

Controls: the iOS switch (`TOGGLE_W` × `TOGGLE_H`, knob `TOGGLE_KNOB`, white in both
states with a shadow); a segmented control where two to `Controls.SEGMENT_MAX` short
options fit side by side, measured at the font in use; a dropdown (reusing the
context-menu component) when they do not; a slider with a live value; a colour swatch that
opens the client colour picker through a compat wrapper.

Segments are the control iOS reaches for with two or three short answers, and a menu is
the fallback — so a choice that fits as segments is allowed more than the standard control
column, and the label shrinks to match down to a floor. Both the control column and the
navigation column are multiplied by the type ramp.

A search field filters all categories, not just the one you are standing in. Appearance
changes apply **live** to the real messenger behind the panel.

### 4.15 Icons

One sheet, drawn as line art at 64 px and tinted at draw time — never coloured art, never
a file per state. Sizes are named (`ICON_GLYPH`, `ICON_GLYPH_SM`, `MENU_ICON`,
`ICON_MARK`, `STATUS_ICON`) and `Tools/test/check_icon_legibility.py` downsamples every
icon to every size it is actually drawn at and fails the build if the shape dissolves.

Every icon is addressed by a **semantic name** — `delivered`, `mute`, `up` — which
resolves either to a drop-in `Media/Icons/<name>.tga` or, failing that, to a cell in the
sheet. Dropping a file in is the whole workflow: no atlas regeneration, no UV editing, no
conversion step. A client that cannot tell whether a file exists stays on the built-in
art rather than showing nothing. `docs/ICON-REPLACEMENT.md` is the per-icon manifest, and
it is generated from the source rather than written by hand.

---

## 5. Motion

| Token     | ms  | Curve       | Used for |
|-----------|-----|-------------|----------|
| `fast`    | 100 | out-quad    | hover, press, badge |
| `base`    | 160 | out-cubic   | fades, crossfades, list scroll |
| `slow`    | 240 | out-cubic   | panels, toasts, menus |
| `window`  | 280 | out-back(1.03) | window open/close, Exposé |

Rules:
* No permanent `OnUpdate`. One shared driver ticks **only** while tweens exist and
  unregisters itself when the queue empties.
* WoW `AnimationGroup`s are used for pure alpha/scale/translate; the driver is used for
  colour, size and scroll interpolation which AnimationGroups cannot express.
* Levels: `Off` (all durations 0) · `Reduced` (×0.6, no scale/slide, no pulses) ·
  `Normal` · `Fancy` (adds bubble pop-in, badge pulse, Exposé zoom).
* Responsiveness always wins: state changes are applied to the model instantly; only the
  *presentation* interpolates.

---

## 6. Skins

A skin is a **complete token set**, not a background colour.

| Skin | Character |
|------|-----------|
| **Midnight** (default) | iOS Dark: Apple's system greys with systemBlue. The skin this document describes. |
| **Messenger** | Warm charcoal canvas, green accent, deep teal outgoing bubbles. |
| **Dark** | Pure neutral greys for people who do not want a colour. |
| **Minimal** | One flat surface, hairlines barely there, generous spacing. |
| **Glass** | Translucent surfaces over the game, stronger hairlines, soft depth. |
| **Classic** | Warm dark parchment with gold, in a modern layout. |

Every skin defines all 35 roles; missing roles inherit from Midnight, so a partial skin can
never render broken. Two more — `trackBg` and `thumbBg` — are derived from `bg3` rather
than written down, so a skin cannot define a control groove nobody can see. Users override
background opacity, font, font size, spacing density, corner radius, class colours,
timestamps and sidebar width on top of any skin.

---

## 7. Client parity

The visual system uses only: `SetColorTexture`, `SetGradient`, `SetTexCoord`,
`CreateMaskTexture` + `AddMaskTexture`, `SetRotation`, `SetClipsChildren`, AnimationGroups,
`SetHyperlinksEnabled`. Each is feature-detected in `Core/Compat` with a documented
fallback, so **Classic Era looks identical to Retail** rather than degrading to a grey box.

Which client it is on is decided once, in `Core/Compat/Compat.lua`, and only ever decides
names and world data — the class count, the `/who` throttle, the folder a player is told
to look in. Never a capability: those are probed, because Blizzard backports into Classic
without warning and a version test is a guess with a date on it.

Forever is the flavour that proves the rule. Its interface files sit in the mainline
family, so `Blizzard_BNet` runs `WOW_PROJECT_ID = WOW_PROJECT_ID or WOW_PROJECT_MAINLINE`
there and the client answers "Retail" to the question every other flavour answers
honestly. The interface number has no such ambiguity, so it is read first.

| Capability | Detection | Fallback |
|-----------|-----------|----------|
| mask textures | `frame.CreateMaskTexture` | rounded-square avatars, square badges |
| `SetClipsChildren` | method probe | `ScrollFrame` clipping |
| gradients (new API) | `tex.SetGradient` arity probe | two-stop colour fill |
| `GetPhysicalScreenSize` | global probe | `GetScreenHeight()` |
| `C_BattleNet` | namespace probe | `BNGetFriendInfo` legacy path |
| colour picker | `ColorPickerFrame.SetupColorPickerAndShow` | legacy field assignment |

---

## 8. Definition of done (per view)

A view ships only when all of these are true:

Alignment on the 4 px grid · consistent padding with its siblings · every interactive
element has hover + pressed + disabled · focus is visible · empty state exists · text
truncates with `Text.ELLIPSIS` instead of overflowing · nothing shifts by ±1 px when
state changes · no element uses a colour literal · works at `WINDOW_MIN_W` · works at
UI scale 0.53 · works at every step of the font-size setting, measured rather than
assumed · survives 5 000 messages in the list without a frame drop.
