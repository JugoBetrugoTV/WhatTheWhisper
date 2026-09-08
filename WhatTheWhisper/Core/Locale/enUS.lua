-- WhatTheWhisper -- English (source language).
local L = LibStub("AceLocale-3.0"):NewLocale("WhatTheWhisper", "enUS", true, true)
if not L then return end

-- Window chrome
L["WhatTheWhisper"] = true
L["Conversations"] = true
L["Search conversations"] = true
L["Search messages"] = true
L["Character details"] = true
L["Class, level, guild, zone and realm under the header."] = true
L["Class"] = true
L["Race"] = true
L["Guild"] = true
L["Zone"] = true
L["Realm"] = true
L["BattleTag"] = true
L["Character"] = true
L["not known"] = true
L["Looking up..."] = true
L["Try again in a moment"] = true
L["New conversation"] = true
L["Settings"] = true
L["All windows"] = true
L["Show every open conversation window side by side."] = true
L["Click a window to go to it, or press Escape"] = true
L["Minimize"] = true
L["Close"] = true
L["Maximize"] = true
L["Restore"] = true
L["Pop out"] = true
L["Dock"] = true
L["Pin"] = true
L["Unpin"] = true
L["Back"] = true

-- Composer
L["Message %s..."] = true
L["Type a message..."] = true
L["Send"] = true
L["Emoji"] = true
L["%d characters over the limit"] = true
L["Will be sent as %d messages"] = true

-- Conversation states
L["Today"] = true
L["Yesterday"] = true
L["Online"] = true
L["Offline"] = true
L["Away"] = true
L["Busy"] = true
L["Muted"] = true
L["Pinned"] = true
L["You"] = true
L["Delivered"] = true
L["Sending"] = true
L["Not delivered"] = true
L["%s is not online"] = true
L["There is no character named %s."] = true
L["Character names are 2 to 12 letters, with no spaces, numbers or punctuation."] = true
L["That realm name is not valid."] = true
L["A BattleTag looks like Name#1234."] = true
L["%d new messages"] = true
L["1 new message"] = true
L["Level %d"] = true
L["Battle.net"] = true

-- Empty states
L["No conversations yet"] = true
L["Whisper someone to start a conversation."] = true
L["Pick a conversation"] = true
L["Your whispers are kept here, one thread per player."] = true
L["No matches"] = true
L["Try a different name or word."] = true
L["Start the conversation"] = true
L["Say hi to %s."] = true
L["History is off"] = true
L["Enable it in Settings > History to keep messages."] = true
L["Nothing to show"] = true

-- Context menu
L["Whisper"] = true
L["Invite to group"] = true
L["Add friend"] = true
L["Ignore"] = true
L["Copy name"] = true
L["Copy message"] = true
L["Copy conversation"] = true
L["Export conversation"] = true
L["Clear history"] = true
L["Mute conversation"] = true
L["Unmute conversation"] = true
L["Pin conversation"] = true
L["Unpin conversation"] = true
L["Close conversation"] = true
L["Target"] = true
L["Look up"] = true
L["Mark as read"] = true
L["Mark as unread"] = true
L["Copy URL"] = true
L["Open in copy box"] = true

-- Dialogs
L["Copy"] = true
L["Press Ctrl+C to copy, then Esc to close."] = true
L["Press Ctrl+C to copy, or save it to a file."] = true
L["Save to file"] = true
L["Saved. It is in %s after your next reload or logout."] = true
L["That conversation is too large to save."] = true
L["There was nothing to save."] = true
L["Export"] = true
L["Format"] = true
L["Plain text"] = true
L["BBCode"] = true
L["Markdown"] = true
L["CSV"] = true
L["Clear this conversation?"] = true
L["Clear all history?"] = true
L["This removes %d stored messages. It cannot be undone."] = true
L["This removes every stored message in %d conversations. It cannot be undone."] = true
L["Cancel"] = true
L["Confirm"] = true
L["Delete"] = true

-- Settings categories
L["General"] = true
L["Appearance"] = true
L["Messages"] = true
L["History"] = true
L["Sounds"] = true
L["Notifications"] = true
L["Animations"] = true
L["Tabs"] = true
L["Windows"] = true
L["Combat"] = true
L["Links"] = true
L["Emoticons"] = true
L["Advanced"] = true
L["Search settings"] = true
L["No settings match your search"] = true
L["Try a shorter word, or clear the search."] = true
L["Nothing here yet"] = true

-- Settings: general
L["Enable WhatTheWhisper"] = true
L["Route whispers into the messenger instead of the default chat frame."] = true
L["Hide whispers from chat frames"] = true
L["Whispers still arrive normally, they are just not printed in the chat window."] = true
L["Open on new whisper"] = true
L["Show the messenger automatically when someone whispers you."] = true
L["Auto-switch to new conversations"] = true
L["Switching away from what you are reading is off by default."] = true
L["Minimap button"] = true
L["Show a button on the minimap to toggle the messenger."] = true
L["Keep messenger open in combat"] = true

-- Settings: appearance
L["Skin"] = true
L["Font"] = true
L["Font size"] = true
L["Background opacity"] = true
L["Corner radius"] = true
L["Density"] = true
L["Comfortable"] = true
L["Compact"] = true
L["Sidebar width"] = true
L["Use class colours"] = true
L["Show timestamps"] = true
L["Timestamp format"] = true
L["24 hour"] = true
L["12 hour"] = true
L["Show avatars"] = true
L["Avatar style"] = true
L["Automatic"] = true
L["Class icon"] = true
L["Initials"] = true
L["Chat bubbles"] = true
L["Group messages"] = true
L["Collapse consecutive messages from the same player."] = true
L["Show date separators"] = true
L["Bubble opacity"] = true
L["Message spacing"] = true

-- Settings: layout
L["Layout"] = true
L["Sidebar"] = true
L["Tabbed"] = true
L["Hybrid"] = true
L["Close tabs after"] = true
L["Never"] = true
L["%d minutes"] = true
L["Blink unread tabs"] = true
L["Open a tab for every conversation"] = true
L["Snap windows together"] = true
L["Lock window position"] = true
L["Remember window positions"] = true

-- Settings: history
L["Keep history"] = true
L["Disabled"] = true
L["This session"] = true
L["1 day"] = true
L["7 days"] = true
L["30 days"] = true
L["Unlimited"] = true
L["Max messages per conversation"] = true
L["Max conversations"] = true
L["Stored messages: %d in %d conversations"] = true
L["Estimated size: %s"] = true
L["Clear all history"] = true

-- Settings: sounds
L["Sound on new message"] = true
L["Sound when window is hidden"] = true
L["Sound on mention"] = true
L["Sound when opening a conversation"] = true
L["Repeat sound cooldown"] = true
L["%d seconds"] = true
L["Do not disturb"] = true
L["Silence everything until you turn this off."] = true
L["Mute in combat"] = true
L["Mute in dungeons"] = true
L["Mute in raids"] = true
L["Mute in arenas"] = true
L["Mute in battlegrounds"] = true
L["None"] = true
L["Custom file"] = true
L["Sound file path"] = true

-- Settings: notifications
L["Show toast notifications"] = true
L["Toast position"] = true
L["Top right"] = true
L["Top left"] = true
L["Bottom right"] = true
L["Bottom left"] = true
L["Toast duration"] = true
L["Flash taskbar icon"] = true
L["Show unread badge"] = true
L["Summarise repeated messages"] = true

-- Settings: animations
L["Animation level"] = true
L["Off"] = true
L["Reduced"] = true
L["Normal"] = true
L["Fancy"] = true
L["Smooth scrolling"] = true

-- Settings: combat
L["Entering combat"] = true
L["Do nothing"] = true
L["Fade conversations"] = true
L["Minimize conversations"] = true
L["Hide conversations"] = true
L["Leaving combat"] = true
L["Restore previous state"] = true
L["Stay hidden"] = true
L["Combat fade opacity"] = true

-- Settings: links and emoticons
L["Detect links"] = true
L["Highlight links in messages and make them clickable."] = true
L["Link colour"] = true
L["Emoticon style"] = true
L["Text"] = true
L["Coloured text"] = true
L["Images"] = true
L["Convert raid target markers"] = true

-- Settings: advanced
L["Debug messages"] = true
L["Reset everything"] = true
L["Profile"] = true
L["Diagnostics"] = true
L["Client"] = true
L["Reset window positions"] = true

-- Emoji picker
L["Smileys"] = true
L["Symbols"] = true
L["Markers"] = true
L["Recent"] = true

-- Toast / notifications
L["%s is offline. Message not delivered."] = true
L["Message too long, sent as %d parts."] = true

-- Slash command help
L["Commands:"] = true
L["/wtw - toggle the messenger"] = true
L["Right-click for the list"] = true
L["Mark all as read"] = true
L["Hide minimap button"] = true
L["/wtw config - open settings"] = true
L["/wtw <name> - open a conversation"] = true
L["/wtw clear - clear all history"] = true
L["/wtw diag - print client diagnostics"] = true

-- Settings labels added with the schema
L["Drop shadows"] = true
L["Square"] = true
L["Round"] = true
L["Always"] = true
L["Timestamp on hover"] = true
L["Maximum toasts"] = true
L["Show delivery state"] = true
L["Show whether the server accepted each message you send."] = true
L["Mark read when focused"] = true
L["Timestamps"] = true
L["Reset all settings?"] = true
L["Every option goes back to its default. Message history is not touched."] = true
L["Reset"] = true
L["Enter a character name"] = true
L["Name"] = true
L["Open"] = true
L["Whisper a player"] = true
L["Something went wrong repeatedly, so whispers are being shown in the chat frame again. /wtw debug for details."] = true
L["Debug logging on."] = true
L["Debug logging off."] = true
L["/wtw show / hide - open or close the messenger"] = true
L["/wtw debug - toggle developer logging"] = true
L["/wtw reset - restore default settings"] = true
L["WhatTheWhisper is ready. Type /wtw to open it."] = true
L["Theme"] = true
L["Typography"] = true
L["Show chat bubbles"] = true
L["Delivery"] = true
L["Mode"] = true
L["Nothing logged yet."] = true
L["/wtw debug log - show the last few entries"] = true
L["Open when you start a whisper"] = true
L["Typing /w in the default chat box opens that conversation here."] = true
