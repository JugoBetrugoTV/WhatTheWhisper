-- WhatTheWhisper -- Copy and export.
--
-- Everything is produced as plain text and handed to an EditBox that is already
-- focused and fully selected, so Ctrl+C is the only step. There is no clipboard
-- API in WoW and nothing here pretends otherwise.

local _, ns = ...
local Compat, Format, Text = ns.Compat, ns.Format, ns.Text
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local Export = {}
ns.Export = Export

local MSG_TS, MSG_DIR, MSG_TEXT = ns.MSG_TS, ns.MSG_DIR, ns.MSG_TEXT
local concat, format, gsub = table.concat, string.format, string.gsub

Export.FORMATS = {
	{ id = "text",     label = L["Plain text"] },
	{ id = "markdown", label = L["Markdown"] },
	{ id = "bbcode",   label = L["BBCode"] },
	{ id = "csv",      label = L["CSV"] },
}

local function senderName(conv, direction)
	if direction == ns.DIR_OUT then return L["You"] end
	return conv.name or Compat.ShortName(conv.id)
end

local function clean(text)
	-- Strip WoW markup so the export is readable outside the game, but keep the
	-- visible text of item links.
	return Text.Strip(text or "")
end

--------------------------------------------------------------------------------
-- Formatters
--------------------------------------------------------------------------------

local writers = {}

writers.text = function(conv, messages)
	local out = {}
	out[#out + 1] = format("%s - %s", "WhatTheWhisper", conv.name or conv.id)
	if conv.realm then out[#out] = out[#out] .. format(" (%s)", conv.realm) end
	out[#out + 1] = Format.ExportStamp()
	out[#out + 1] = string.rep("-", 46)
	local lastDay
	for i = 1, #messages do
		local m = messages[i]
		local day = Format.DayStart(m[MSG_TS])
		if day ~= lastDay then
			lastDay = day
			out[#out + 1] = ""
			out[#out + 1] = format("--- %s ---", Format.DayLabel(m[MSG_TS]))
		end
		out[#out + 1] = format("[%s] %s: %s",
			Format.Clock(m[MSG_TS]), senderName(conv, m[MSG_DIR]), clean(m[MSG_TEXT]))
	end
	return concat(out, "\n")
end

writers.markdown = function(conv, messages)
	local out = {}
	out[#out + 1] = format("## %s", conv.name or conv.id)
	out[#out + 1] = format("*%s*", Format.ExportStamp())
	out[#out + 1] = ""
	local lastDay
	for i = 1, #messages do
		local m = messages[i]
		local day = Format.DayStart(m[MSG_TS])
		if day ~= lastDay then
			lastDay = day
			out[#out + 1] = format("### %s", Format.DayLabel(m[MSG_TS]))
		end
		out[#out + 1] = format("**%s** `%s`  ",
			senderName(conv, m[MSG_DIR]), Format.Clock(m[MSG_TS]))
		out[#out + 1] = clean(m[MSG_TEXT])
		out[#out + 1] = ""
	end
	return concat(out, "\n")
end

writers.bbcode = function(conv, messages)
	local out = {}
	out[#out + 1] = format("[b]%s[/b]", conv.name or conv.id)
	out[#out + 1] = "[quote]"
	for i = 1, #messages do
		local m = messages[i]
		out[#out + 1] = format("[b][%s] %s:[/b] %s",
			Format.Clock(m[MSG_TS]), senderName(conv, m[MSG_DIR]), clean(m[MSG_TEXT]))
	end
	out[#out + 1] = "[/quote]"
	return concat(out, "\n")
end

writers.csv = function(conv, messages)
	local out = { "timestamp,time,direction,sender,message" }
	for i = 1, #messages do
		local m = messages[i]
		local body = gsub(clean(m[MSG_TEXT]), '"', '""')
		out[#out + 1] = format('%d,"%s",%s,"%s","%s"',
			m[MSG_TS], Format.ExportStamp(m[MSG_TS]),
			m[MSG_DIR] == ns.DIR_OUT and "out" or "in",
			gsub(senderName(conv, m[MSG_DIR]), '"', '""'), body)
	end
	return concat(out, "\n")
end

--------------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------------

function Export.Conversation(conv, formatID, fromIndex, toIndex)
	if not conv then return "" end
	local writer = writers[formatID or "text"] or writers.text
	local all = conv.messages
	local messages = all
	if fromIndex or toIndex then
		messages = {}
		for i = fromIndex or 1, toIndex or #all do
			messages[#messages + 1] = all[i]
		end
	end
	local ok, result = pcall(writer, conv, messages)
	if not ok then
		ns.SoftError("Export", result)
		return ""
	end
	return result
end

function Export.Message(conv, msg, formatID)
	if not msg then return "" end
	if formatID == "bbcode" then
		return format("[b]%s[/b] %s", senderName(conv, msg[MSG_DIR]), clean(msg[MSG_TEXT]))
	elseif formatID == "markdown" then
		return format("**%s** %s", senderName(conv, msg[MSG_DIR]), clean(msg[MSG_TEXT]))
	end
	return format("[%s] %s: %s",
		Format.Clock(msg[MSG_TS]), senderName(conv, msg[MSG_DIR]), clean(msg[MSG_TEXT]))
end

function Export.PlainMessage(msg)
	return clean(msg and msg[MSG_TEXT])
end

--------------------------------------------------------------------------------
-- Export to a file
--------------------------------------------------------------------------------

-- The client cannot write a file the player chooses, and it has no clipboard.
-- What it does have is saved variables, which are written to a real .lua file on
-- disk when the session ends. So "export to file" is a saved variable: the text
-- goes in, and after a reload or a logout it is sitting in a text file the
-- player can open in any editor.
--
-- Kept out of the settings database on purpose. That one is loaded, merged and
-- written back on every login; an export is a one-off the player takes away, and
-- growing the profile with it would slow down every future login.
Export.MAX_FILE_BYTES = 4 * 1024 * 1024

-- Where the file lands, in the words the player needs to find it.
function Export.FilePath()
	local folder = ns.Compat.SavedVariablesFolder and ns.Compat.SavedVariablesFolder()
	return (folder or "WTF\\Account\\<account>\\SavedVariables")
		.. "\\WhatTheWhisper.lua"
end

-- Returns true plus the byte count, or false plus a reason.
function Export.ToFile(conv, formatID)
	if not conv then return false, "empty" end
	local text = Export.Conversation(conv, formatID)
	if not text or text == "" then return false, "empty" end
	if #text > Export.MAX_FILE_BYTES then return false, "toobig" end

	local store = _G.WhatTheWhisperExportDB
	if type(store) ~= "table" then
		store = {}
		_G.WhatTheWhisperExportDB = store
	end
	-- One slot per conversation and format, so exporting twice replaces rather
	-- than piles up, and the file stays something a person can read.
	store.exports = type(store.exports) == "table" and store.exports or {}
	store.exports[conv.id .. "." .. (formatID or "text")] = {
		conversation = conv.name or conv.id,
		format = formatID or "text",
		savedAt = Format.ExportStamp(),
		text = text,
	}
	store.readme = ns.EXPORT_README
	return true, #text
end

function Export.ClearFile()
	_G.WhatTheWhisperExportDB = nil
end
