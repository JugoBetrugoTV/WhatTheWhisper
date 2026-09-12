# WhatTheWhisper — Design System

> A messenger that happens to live inside World of Warcraft.
> Target quality bar: Telegram Desktop / Discord / Apple Messages — not "WoW addon".

This document is the **contract** between design and code. Every number in here exists as a
named constant in `Core/Namespace.lua` (`ns.S`, `ns.SZ`, `ns.T`, `ns.R`, `ns.MOTION`).
No magic numbers are allowed anywhere else in the codebase.

---

## 0. Design principles

1. **Calm surfaces, loud content.** Chrome is near-monochrome; colour is reserved for the
   accent (selection, unread, own messages) and class colours. Nothing else is coloured.
2. **Hierarchy through value, not weight.** WoW ships no bold font cut. Emphasis is created
   with *brightness* and *size*, never with fake outlines or shadows on text.
3. **One radius family, one spacing family.** 4 / 8 / 12 / 16 / 20 / 24 / 32. Nothing else.
4. **Every interactive element has five states**: rest, hover, pressed, selected, disabled.
   A control without a hover state is an unfinished control.
5. **Motion is feedback, never decoration.** 100–260 ms, ease-out. Nothing loops forever.
6. **Identical on all four clients.** No feature or visual may exist on Retail only.

---

## 1. Layout

### 1.1 Main window

```
┌──────────────────────────────────────────────────────────────────────┐
│ ●  WhatTheWhisper                            [⌗] [≡] [–] [✕]         │ 36  Titlebar
├───────────────────────────┬──────────────────────────────────────────┤
│  ⌕  Search           [+]  │  ◗ Thrall                     [⌕][⧉][⋯]  │ 52 / 56
├───────────────────────────┼──────────────────────────────────────────┤
│ ◗ Thrall           22:41  │  ──────────── Today ────────────         │
│   Yo kommst du Raid?   ②  │                                          │
│ ─────────────────────────  │  ◗ Thrall  22:41                        │
│ ◗ Jaina            21:07  │    ╭──────────────────────╮              │
│   Portal in 5              │    │ Yo kommst du Raid?   │              │
│ ─────────────────────────  │    ╰──────────────────────╯              │
│ ◗ Sylvanas         Mon    │                    ╭───────────────────╮ │
│   ...                      │                    │ Ja bin gleich da  │ │
│                            │                    ╰───────────────────╯ │
│                            ├──────────────────────────────────────────┤
│                            │ ☺ │ Message Thrall…            │  ↑     │ 60  Composer
└───────────────────────────┴──────────────────────────────────────────┘
   288 sidebar
```

Layer stack (back → front), each layer differs by **brightness only**:

| Layer          | Role                                   |
|----------------|----------------------------------------|
| `bg0`          | window base / titlebar                 |
| `bg1`          | sidebar column                         |
| `bg2`          | conversation surface (message canvas)  |
| `bg3`          | raised: composer field, cards, menus, tooltips, popouts |
| `hover`        | +6 % white over the owning layer       |
| `selected`     | +11 % white over the owning layer      |
| `scrim`        | 62 % black, full screen (Exposé/modal) |

Separation between columns is a **1 physical-pixel hairline** at `borderSubtle`, never a
3-D bevel, never a Blizzard backdrop edge.

### 1.2 Metrics

| Constant                 | px   | Notes |
|--------------------------|------|-------|
| `WINDOW_W / WINDOW_H`    | 940 × 580 | default |
| `WINDOW_MIN_W / MIN_H`   | 660 × 420 | hard floor |
| `TITLEBAR_H`             | 36 |
| `SIDEBAR_W`              | 288 | user resizable 220–420 |
| `SIDEBAR_COMPACT_AT`     | 232 | below → 68 px icon rail |
| `SIDEBAR_HEADER_H`       | 52 |
| `ROW_H` / `ROW_H_COMPACT`| 64 / 52 |
| `HEADER_H`               | 56 |
| `TAB_H`                  | 36 |
| `COMPOSER_MIN_H`         | 60 | grows to `COMPOSER_MAX_H` 140 |
| `AVATAR_LG/MD/SM/XS`     | 40 / 32 / 24 / 18 |
| `BADGE_H`                | 18 | pill, min width 18 |
| `ICON_BTN`               | 30 | 16 px glyph centred |
| `SEND_BTN`               | 32 | circular, accent |
| `SCROLLBAR_W`            | 4 | 10 px hit area, auto-hide |
| `LIST_PAD_X / LIST_PAD_Y`| 20 / 16 |

### 1.3 Responsive rules

| Width                   | Behaviour |
|-------------------------|-----------|
| `< 232` sidebar         | avatar-only rail; name/preview/time hidden, badge overlays avatar |
| `< 760` window          | sidebar auto-narrows to 232 before the conversation gives up space |
| `< 660` window          | blocked by min size |
| any                     | bubbles cap at `min(66 % of canvas, 560 px)` so ultrawide never stretches text |

Everything is laid out with anchors + explicit sizes, and every hairline is snapped to a
physical pixel (`ns.Pixel`), so 1080p / 1440p / 4K and UI-scale 0.53–1.0 all render crisp.

---

## 2. Typography

Five sizes, no more. Font path is derived from `ChatFontNormal` at runtime so every locale
(incl. ruRU / koKR / zhCN) gets a valid face; user-selectable faces are validated before use.

| Token       | px | Use |
|-------------|----|-----|
| `T.micro`   | 11 | timestamps, badge counts, meta chips |
| `T.small`   | 12 | last-message preview, secondary labels, empty-state body |
| `T.body`    | 14 | message text, contact name, input text |
| `T.title`   | 16 | conversation header name, section titles |
| `T.display` | 18 | empty-state headline |

* Line spacing for message bodies: **3 px**. Everything else: default.
* No `OUTLINE` flags anywhere in chrome (outlines are the #1 "2010 addon" tell). Optional
  outline exists only for the *message text* skin setting, off by default.
* Emphasis ladder: `textMuted` → `textSecondary` → `textPrimary` → `accent`.

---

## 3. Colour

Roles are skin-defined; the code never names a literal colour. Reference values below are
the default skin **Midnight**.

| Role           | Midnight   | Meaning |
|----------------|-----------|---------|
| `bg0`          | `#0E1116` | base |
| `bg1`          | `#12161C` | sidebar |
| `bg2`          | `#161B22` | canvas |
| `bg3`          | `#1C222B` | raised |
| `hover`        | white 6 % | |
| `selected`     | white 11 % | |
| `borderSubtle` | white 7 % | hairlines |
| `borderStrong` | white 14 % | focus rings, dividers that must read |
| `accent`       | `#5A7CFA` | selection, unread, own bubbles, focus |
| `accentHover`  | `#7190FF` | |
| `onAccent`     | `#FFFFFF` | |
| `textPrimary`  | `#E8ECF2` | |
| `textSecondary`| `#A7B0BE` | |
| `textMuted`    | `#6E7785` | |
| `textDisabled` | `#4A515C` | |
| `bubbleIn`     | `#1E2530` | |
| `bubbleOut`    | `#2C3F6B` | accent-tinted, never pure accent (unreadable) |
| `success`      | `#3FBF7F` | delivered tick, online dot |
| `danger`       | `#E5484D` | failed send, destructive menu items |
| `warning`      | `#E8B84B` | |

Class colours are used **only** for: avatar ring/fill, contact name, bubble sender name —
and only when `appearance.classColors` is on. They never colour backgrounds.

---

## 4. Components

### 4.1 Conversation row (sidebar)

```
 ┃ ╭──╮  Thrall                       22:41
 ┃ │◉ │  Yo kommst du Raid?             ②
   ╰──╯
 ▲ 3 px accent bar, selected only         64 px tall
```

* padding `16 / 12`, avatar `40`, gap `12`
* name `T.body` `textPrimary`; unread → name stays primary, **preview** lifts
  `textMuted → textSecondary` and the badge appears. No bold fakery.
* muted conversation: name drops to `textSecondary`, mute glyph after the name, badge
  renders in `textMuted` instead of accent
* pinned: pin glyph before the timestamp; pinned rows sort above the rest
* hover: `hover` fill, 140 ms; selected: `selected` fill + 3 px accent bar with 2 px radius
* pressed: `selected` fill immediately (no animation) — clicks must feel instant

### 4.2 Avatar

Circular (mask), three sources with graceful fallback:
`portrait (unit in range) → class icon → class-coloured disc with UTF-8 initial`.
Optional 8 px status dot (bottom-right) with a 2 px cut-out ring in the owning layer colour.
If `CreateMaskTexture` is unavailable the avatar degrades to a rounded square — same size,
same palette, so layout never shifts.

### 4.3 Message bubble

* max width `min(66 %, 560)`, padding `11 / 7`, radius `12`
* the corner facing the group's "spine" uses radius `4` (tail)
* incoming: left, `bubbleIn`; outgoing: right, `bubbleOut`
* **Grouping**: same sender + same type + ≤ 300 s apart → one group.
  First bubble of a group carries avatar + `Name · 22:41`; the rest are bare, 2 px apart.
* per-message timestamp appears on hover on the outer side (option: always)
* outgoing status glyph, 10 px, right of the timestamp:
  `pending (muted dot) → sent (✓, success)` and `failed (✕, danger)` when the server
  replies "no player named …". This is real delivery information, not a simulation.
* selection/copy: hover reveals a 20 px overflow affordance → per-message menu

### 4.4 Date separator

Centred pill on `bg3` at 55 % opacity, `T.micro`, `textMuted`, 20 px above / 12 px below.
No rules, no lines: `Today` / `Yesterday` / weekday / `dd.mm.yyyy` (locale aware).

### 4.5 Composer

`bg3` rounded field (radius 8) inset 12 px from the composer strip, internal padding 12/8.
Left: emoji button (30). Right: circular send button (32) that fades from `textMuted` to
`accent` the moment the field is non-empty — the single most satisfying micro-interaction
in the app. Focus draws a 1 px `accent` ring plus a 1 px `accent @ 22 %` outer glow.
Placeholder: *"Message Thrall…"*. `Enter` sends, `Shift+Enter` newline, `Esc` blurs.
Multi-line input is split into whisper-legal chunks (255 **bytes**, UTF-8 safe, word-aware).
A character counter appears only at ≥ 200 bytes, in `textMuted`, `danger` past the limit.

### 4.6 Tabs

Browser-style, not Blizzard registers: 36 px tall, radius 8 on the top corners only,
inactive on `bg1`, active raised to `bg2` so it visually merges with the canvas below.
Unread → 6 px accent dot left of the label. Close button appears on hover (or when active).
Drag to reorder with a 150 ms slide of the displaced neighbours.

### 4.7 Buttons

| Kind        | Height | Radius | Rest | Hover | Pressed | Disabled |
|-------------|--------|--------|------|-------|---------|----------|
| Icon        | 30     | 8      | glyph `textSecondary` | `hover` fill, glyph `textPrimary` | `selected` fill | glyph `textDisabled` |
| Primary     | 32     | 8      | `accent` fill, `onAccent` | `accentHover` | `accent` −8 % | 40 % alpha |
| Ghost       | 30     | 8      | transparent, `textSecondary` | `hover` fill | `selected` | `textDisabled` |
| Destructive | 30     | 8      | transparent, `danger` | `danger @ 14 %` fill | `danger @ 22 %` | 40 % |

### 4.8 Context menu

Own implementation (no `UIDropDownMenu` → no taint, full design control).
`bg3`, radius 8, 1 px `borderSubtle`, 6 px vertical padding, item height 28, icon 14 at
10 px inset, label `T.small`. Separator = 1 px hairline with 6 px margins. Destructive
items are `danger` and always sit last, below a separator. Opens with a 90 ms fade + 4 px
rise; a full-screen invisible catcher closes it on any outside click or `Esc`.

### 4.9 Tooltip

Own frame. `bg3`, radius 6, padding 8/5, `T.micro`, single line, 350 ms delay, 90 ms fade.
Never taller than two lines. Blizzard's `GameTooltip` is used **only** for real game
hyperlinks (items, spells, achievements) inside message text, where it is the correct tool.

### 4.10 Toast notification

Top-right stack (corner configurable), 320 × 62, `bg3`, radius 12, 1 px `borderSubtle`,
avatar 32 + name `T.body` + one clamped preview line `T.small`. Enters with a 16 px slide
from the edge + fade over 200 ms, auto-dismisses after 5 s with a hairline progress bar in
`accent`. Hover pauses the timer; click opens the conversation.

### 4.11 Scrolling

* Custom 4 px scrollbar (10 px hit area), `borderStrong`, radius 2. Hidden at rest, fades
  in on hover-over-list or during scroll, fades out 900 ms after the last movement.
* **Smart auto-scroll**: pinned to bottom → new messages scroll in. Scrolled up → the view
  does *not* move; instead a pill appears above the composer:
  `↓ 3 new messages`, `accent` fill, click → smooth scroll to bottom.
* Wheel scroll animates over 140 ms (`Reduced`/`Off` → instant).

### 4.12 Empty states

Centred, max 320 px wide, vertically at 42 % height (optically centred, not mathematically).

| Situation | Headline (`T.display`, `textSecondary`) | Body (`T.small`, `textMuted`) |
|-----------|------------------------------------------|-------------------------------|
| no conversations | No conversations yet | Whisper someone to start a conversation. |
| nothing selected | Pick a conversation | Your whispers stay here, per player. |
| search empty | No matches | Try a different name or word. |
| history empty | Start the conversation | Say hi to %s. |
| history disabled | History is off | Enable it in Settings › History to keep messages. |

Each carries a 40 px line-art glyph drawn from the same icon primitives at 20 % alpha.

### 4.13 Settings

Left nav 200 px (`bg1`, 32 px rows, accent bar on active), right content on `bg2`, max
content width 640 centred. Settings are grouped into **cards** (`bg3`, radius 12, padding
16, 12 px gaps) with a `T.small`/`textMuted` caption under each control label.
Controls: animated toggle (36 × 20, knob 16, 140 ms), custom slider (4 px track, 14 px
thumb, live value chip), custom dropdown (reuses the context-menu component), colour swatch
(opens the client colour picker through a compat wrapper). A search field filters all
categories. Appearance changes apply **live** to the real messenger behind the panel.

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
| **Midnight** (default) | Very dark blue-grey, indigo accent, high contrast text. Battle.net-adjacent, premium. |
| **WhatsApp-inspired** | Warm charcoal canvas, green accent `#25D366`, teal-dark outgoing bubbles, larger radii (16). |
| **Dark** | Pure neutral greys, cyan-less, minimal chroma. For people who hate blue. |
| **Minimal** | Almost borderless, `bg1 == bg2`, bubbles are text with 4 px radius and no fill on incoming, generous spacing (+4 everywhere). |
| **Glass** | Low-opacity layers (0.62–0.78) over the game, stronger hairlines, soft outer shadow, accent `#8AA6FF`. |
| **Classic** | Warm parchment-dark palette with gold accent and slightly heavier borders — WoW *flavoured*, not Blizzard *framed*. |

Every skin defines all 24 roles; missing roles inherit from Midnight, so a partial skin can
never render broken. Users override background opacity, font, font size, spacing density,
corner radius, class colours, timestamps and sidebar width on top of any skin.

---

## 7. Client parity

The visual system uses only: `SetColorTexture`, `SetGradient`, `SetTexCoord`,
`CreateMaskTexture` + `AddMaskTexture`, `SetRotation`, `SetClipsChildren`, AnimationGroups,
`SetHyperlinksEnabled`. Each is feature-detected in `Core/Compat` with a documented
fallback, so **Classic Era looks identical to Retail** rather than degrading to a grey box.

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
truncates with `…` instead of overflowing · nothing shifts by ±1 px when state changes ·
no element uses a colour literal · works at 660 px width · works at UI scale 0.53 ·
survives 5 000 messages in the list without a frame drop.
