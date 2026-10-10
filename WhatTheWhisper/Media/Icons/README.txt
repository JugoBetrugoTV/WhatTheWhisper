WhatTheWhisper -- drop-in icons
===============================

Put a .tga file in this folder named after the icon you want to replace, reload
the interface (/reload), and the addon uses it. Nothing else to do: no Lua to
edit, no sprite sheet to rebuild, no coordinates to work out.

    WhatTheWhisper/Media/Icons/send.tga      <- replaces the send button's mark
    WhatTheWhisper/Media/Icons/search.tga    <- replaces the magnifier
    ...

Anything you do not put here keeps using the built-in artwork, so you can
replace the set one file at a time and the window always works.

The full list of filenames, what each one is for, what size it is drawn at and
what it should look like, is in:

    WhatTheWhisper/docs/ICON-REPLACEMENT.md

File format
-----------
  * 32-bit TGA (with an alpha channel), uncompressed
  * 64 x 64 pixels for ordinary glyphs, 128 x 128 for the logo
  * transparent background
  * white or light grey shapes

Draw them white. The addon tints every icon to match the active theme, so one
white file works in all six skins; a blue one stays blue in the green skin.

Leave a little breathing room inside the square -- the manifest gives a padding
figure per icon. Artwork that runs to the edge looks larger than everything
around it once it is scaled down to 18 pixels.
