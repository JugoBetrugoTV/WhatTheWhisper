-- WhatTheWhisper -- 繁體中文。
--
-- `true` 表示「與英文相同」，這是刻意寫下的：產品名稱與檔案格式名稱不翻譯，
-- 在這裡寫清楚，才分得出「我們這樣決定」和「有人漏了一行」。

local _, ns = ...

ns.RegisterLocale("zhTW", {
	-- 視窗
	["WhatTheWhisper"] = true,
	["Conversations"] = "對話",
	["Search conversations"] = "搜尋對話",
	["Search messages"] = "搜尋訊息",
	["Character details"] = "角色資料",
	["Class, level, guild, zone and realm under the header."] =
		"在標題下方顯示職業、等級、公會、區域與伺服器。",
	["Class"] = "職業",
	["Race"] = "種族",
	["Guild"] = "公會",
	["Zone"] = "區域",
	["Realm"] = "伺服器",
	["BattleTag"] = true,
	["Character"] = "角色",
	["not known"] = "未知",
	["Looking up..."] = "查詢中……",
	["Try again in a moment"] = "請稍候再試",
	["New conversation"] = "新增對話",
	["Settings"] = "設定",
	["All windows"] = "所有視窗",
	["Show every open conversation window side by side."] =
		"把所有開啟的對話視窗並排顯示。",
	["Click a window to go to it, or press Escape"] =
		"點選視窗即可切換過去，按 Esc 離開",
	["Minimize"] = "最小化",
	["Close"] = "關閉",
	["Maximize"] = "最大化",
	["Restore"] = "還原",
	["Pop out"] = "獨立視窗",
	["Dock"] = "停靠回去",
	["Pin"] = "釘選",
	["Unpin"] = "取消釘選",
	["Back"] = "返回",

	-- 輸入
	["Message %s..."] = "給 %s 的訊息……",
	["Type a message..."] = "輸入訊息……",
	["Send"] = "傳送",
	["Emoji"] = "表情符號",
	["%d characters over the limit"] = "超出 %d 個字元",
	["Will be sent as %d messages"] = "會分成 %d 則傳送",

	-- 對話狀態
	["Today"] = "今天",
	["Yesterday"] = "昨天",
	["Online"] = "上線中",
	["Offline"] = "已離線",
	["Away"] = "離開",
	["Busy"] = "忙碌",
	["Muted"] = "已靜音",
	["Pinned"] = "已釘選",
	["You"] = "你",
	["Delivered"] = "已送達",
	["Sending"] = "傳送中",
	["Not delivered"] = "未送達",
	["%s is not online"] = "%s 不在線上",
	["There is no character named %s."] = "沒有名為 %s 的角色。",
	["Character names are 2 to 12 letters, with no spaces, numbers or punctuation."] =
		"角色名稱為 2 到 12 個字母，不含空格、數字與標點。",
	["That realm name is not valid."] = "該伺服器名稱無效。",
	["A BattleTag looks like Name#1234."] = "戰網標籤的格式是 名稱#1234。",
	["%d new messages"] = "%d 則新訊息",
	["1 new message"] = "1 則新訊息",
	["Level %d"] = "%d 級",
	["Battle.net"] = true,

	-- 空白狀態
	["No conversations yet"] = "還沒有對話",
	["Whisper someone to start a conversation."] = "密語某人即可開始對話。",
	["Pick a conversation"] = "選一段對話",
	["Your whispers are kept here, one thread per player."] =
		"你的密語都留在這裡，每位玩家一段對話。",
	["No matches"] = "沒有符合的結果",
	["Try a different name or word."] = "換個名稱或字詞試試。",
	["Start the conversation"] = "開始這段對話",
	["Say hi to %s."] = "跟 %s 打聲招呼。",
	["History is off"] = "紀錄已關閉",
	["Enable it in Settings > History to keep messages."] =
		"在「設定 > 紀錄」中開啟後才會保留訊息。",
	["Nothing to show"] = "沒有可顯示的內容",

	-- 右鍵選單
	["Whisper"] = "密語",
	["Invite to group"] = "邀請入隊",
	["Add friend"] = "加為好友",
	["Ignore"] = "忽略",
	["Copy name"] = "複製名稱",
	["Copy message"] = "複製訊息",
	["Copy conversation"] = "複製對話",
	["Export conversation"] = "匯出對話",
	["Clear history"] = "清除紀錄",
	["Mute conversation"] = "將此對話靜音",
	["Unmute conversation"] = "取消靜音",
	["Pin conversation"] = "釘選此對話",
	["Unpin conversation"] = "取消釘選此對話",
	["Close conversation"] = "關閉此對話",
	["Target"] = "選為目標",
	["Look up"] = "查詢",
	["Mark as read"] = "標為已讀",
	["Mark as unread"] = "標為未讀",
	["Copy URL"] = "複製連結",
	["Open in copy box"] = "在複製視窗中開啟",

	-- 對話方塊
	["Copy"] = "複製",
	["Press Ctrl+C to copy, then Esc to close."] = "按 Ctrl+C 複製，再按 Esc 關閉。",
	["Press Ctrl+C to copy, or save it to a file."] = "按 Ctrl+C 複製，或存成檔案。",
	["Save to file"] = "存成檔案",
	["Saved. It is in %s after your next reload or logout."] =
		"已儲存。重新載入介面或登出後可在 %s 找到。",
	["That conversation is too large to save."] = "這段對話太大，無法儲存。",
	["There was nothing to save."] = "沒有可儲存的內容。",
	["Export"] = "匯出",
	["Format"] = "格式",
	["Plain text"] = "純文字",
	["BBCode"] = true,
	["Markdown"] = true,
	["CSV"] = true,
	["Clear this conversation?"] = "清除這段對話？",
	["Clear all history?"] = "清除全部紀錄？",
	["This removes %d stored messages. It cannot be undone."] =
		"這會刪除已儲存的 %d 則訊息，而且無法復原。",
	["This removes every stored message in %d conversations. It cannot be undone."] =
		"這會刪除 %d 段對話中儲存的所有訊息，而且無法復原。",
	["Cancel"] = "取消",
	["Confirm"] = "確定",
	["Delete"] = "刪除",

	-- 設定分類
	["General"] = "一般",
	["Appearance"] = "外觀",
	["Messages"] = "訊息",
	["History"] = "紀錄",
	["Sounds"] = "音效",
	["Notifications"] = "通知",
	["Animations"] = "動畫",
	["Tabs"] = "分頁",
	["Windows"] = "視窗",
	["Combat"] = "戰鬥",
	["Links"] = "連結",
	["Emoticons"] = "表情圖案",
	["Advanced"] = "進階",
	["Search settings"] = "搜尋設定",
	["No settings match your search"] = "沒有設定符合你的搜尋",
	["Try a shorter word, or clear the search."] = "換個更短的字詞，或清空搜尋。",
	["Nothing here yet"] = "這裡還是空的",

	-- 設定：一般
	["Enable WhatTheWhisper"] = "啟用 WhatTheWhisper",
	["Route whispers into the messenger instead of the default chat frame."] =
		"把密語導入訊息視窗，而不是預設的聊天視窗。",
	["Hide whispers from chat frames"] = "在聊天視窗中隱藏密語",
	["Whispers still arrive normally, they are just not printed in the chat window."] =
		"密語照常收得到，只是不會顯示在聊天視窗裡。",
	["Open on new whisper"] = "收到新密語時開啟",
	["Show the messenger automatically when someone whispers you."] =
		"有人密語你時自動顯示訊息視窗。",
	["Auto-switch to new conversations"] = "自動切換到新對話",
	["Switching away from what you are reading is off by default."] =
		"預設不會打斷你正在讀的內容。",
	["Minimap button"] = "小地圖按鈕",
	["Show a button on the minimap to toggle the messenger."] =
		"在小地圖上顯示一個按鈕，用來開關訊息視窗。",
	["Keep messenger open in combat"] = "戰鬥中保持訊息視窗開啟",

	-- 設定：外觀
	["Skin"] = "外觀樣式",
	["Font"] = "字型",
	["Font size"] = "字級",
	["Background opacity"] = "背景不透明度",
	["Corner radius"] = "圓角半徑",
	["Density"] = "疏密",
	["Comfortable"] = "寬鬆",
	["Compact"] = "緊湊",
	["Sidebar width"] = "側欄寬度",
	["Use class colours"] = "使用職業顏色",
	["Show timestamps"] = "顯示時間",
	["Timestamp format"] = "時間格式",
	["24 hour"] = "24 小時制",
	["12 hour"] = "12 小時制",
	["Show avatars"] = "顯示頭像",
	["Avatar style"] = "頭像樣式",
	["Automatic"] = "自動",
	["Class icon"] = "職業圖示",
	["Initials"] = "名稱首字",
	["Chat bubbles"] = "對話框",
	["Group messages"] = "合併訊息",
	["Collapse consecutive messages from the same player."] =
		"把同一位玩家連續傳來的訊息合在一起。",
	["Show date separators"] = "顯示日期分隔線",
	["Bubble opacity"] = "對話框不透明度",
	["Message spacing"] = "訊息間距",

	-- 設定：版面
	["Layout"] = "版面",
	["Sidebar"] = "側欄",
	["Tabbed"] = "分頁",
	["Hybrid"] = "混合",
	["Close tabs after"] = "多久後關閉分頁",
	["Never"] = "永不",
	["%d minutes"] = "%d 分鐘",
	["Blink unread tabs"] = "未讀分頁閃爍",
	["Open a tab for every conversation"] = "每段對話都開一個分頁",
	["Snap windows together"] = "視窗自動貼齊",
	["Lock window position"] = "鎖定視窗位置",
	["Remember window positions"] = "記住視窗位置",

	-- 設定：紀錄
	["Keep history"] = "保留紀錄",
	["Disabled"] = "關閉",
	["This session"] = "這次登入",
	["1 day"] = "1 天",
	["7 days"] = "7 天",
	["30 days"] = "30 天",
	["Unlimited"] = "不限",
	["Max messages per conversation"] = "每段對話最多訊息數",
	["Max conversations"] = "最多對話數",
	["Stored messages: %d in %d conversations"] = "已儲存 %d 則訊息，共 %d 段對話",
	["Estimated size: %s"] = "估計佔用：%s",
	["Clear all history"] = "清除全部紀錄",

	-- 設定：音效
	["Sound on new message"] = "新訊息音效",
	["Sound when window is hidden"] = "視窗隱藏時也發出音效",
	["Sound on mention"] = "被提到時的音效",
	["Sound when opening a conversation"] = "開啟對話時的音效",
	["Repeat sound cooldown"] = "重複音效的間隔",
	["%d seconds"] = "%d 秒",
	["Do not disturb"] = "請勿打擾",
	["Silence everything until you turn this off."] = "在你關掉之前一律靜音。",
	["Mute in combat"] = "戰鬥中靜音",
	["Mute in dungeons"] = "地城中靜音",
	["Mute in raids"] = "團隊地城中靜音",
	["Mute in arenas"] = "競技場中靜音",
	["Mute in battlegrounds"] = "戰場中靜音",
	["None"] = "無",
	["Custom file"] = "自訂檔案",
	["Sound file path"] = "音效檔路徑",

	-- 設定：通知
	["Show toast notifications"] = "顯示彈出通知",
	["Toast position"] = "通知位置",
	["Top right"] = "右上角",
	["Top left"] = "左上角",
	["Bottom right"] = "右下角",
	["Bottom left"] = "左下角",
	["Toast duration"] = "通知停留時間",
	["Flash taskbar icon"] = "閃爍工作列圖示",
	["Show unread badge"] = "顯示未讀數",
	["Summarise repeated messages"] = "合併重複的訊息",

	-- 設定：動畫
	["Animation level"] = "動畫程度",
	["Off"] = "關閉",
	["Reduced"] = "精簡",
	["Normal"] = "正常",
	["Fancy"] = "華麗",
	["Smooth scrolling"] = "平滑捲動",

	-- 設定：戰鬥
	["Entering combat"] = "進入戰鬥時",
	["Do nothing"] = "什麼都不做",
	["Fade conversations"] = "淡化對話視窗",
	["Minimize conversations"] = "最小化對話視窗",
	["Hide conversations"] = "隱藏對話視窗",
	["Leaving combat"] = "脫離戰鬥時",
	["Restore previous state"] = "恢復原狀",
	["Stay hidden"] = "保持隱藏",
	["Combat fade opacity"] = "戰鬥中的不透明度",

	-- 設定：連結與表情圖案
	["Detect links"] = "辨識連結",
	["Highlight links in messages and make them clickable."] =
		"標示訊息中的連結，並讓它可以點選。",
	["Link colour"] = "連結顏色",
	["Emoticon style"] = "表情圖案樣式",
	["Text"] = "文字",
	["Coloured text"] = "彩色文字",
	["Images"] = "圖片",
	["Convert raid target markers"] = "把團隊標記換成圖示",

	-- 設定：進階
	["Debug messages"] = "除錯訊息",
	["Reset everything"] = "全部重設",
	["Profile"] = "設定檔",
	["Diagnostics"] = "診斷",
	["Client"] = "用戶端",
	["Reset window positions"] = "重設視窗位置",

	-- 表情選擇
	["Smileys"] = "笑臉",
	["Symbols"] = "符號",
	["Markers"] = "團隊標記",
	["Recent"] = "最近",

	-- 提示
	["%s is offline. Message not delivered."] = "%s 不在線上，訊息未送達。",
	["Message too long, sent as %d parts."] = "訊息太長，已分成 %d 則傳送。",

	-- 指令說明
	["Commands:"] = "指令：",
	["/wtw - toggle the messenger"] = "/wtw - 開關訊息視窗",
	["Right-click for the list"] = "按右鍵查看清單",
	["Mark all as read"] = "全部標為已讀",
	["Hide minimap button"] = "隱藏小地圖按鈕",
	["/wtw config - open settings"] = "/wtw config - 開啟設定",
	["/wtw <name> - open a conversation"] = "/wtw <名稱> - 開啟對話",
	["/wtw clear - clear all history"] = "/wtw clear - 清除全部紀錄",
	["/wtw diag - print client diagnostics"] = "/wtw diag - 輸出用戶端診斷資訊",

	-- 隨設定結構一併加入的文字
	["Drop shadows"] = "陰影",
	["Square"] = "直角",
	["Round"] = "圓角",
	["Always"] = "永遠",
	["Timestamp on hover"] = "滑鼠移過去時顯示時間",
	["Maximum toasts"] = "同時顯示的通知數",
	["Show delivery state"] = "顯示送達狀態",
	["Show whether the server accepted each message you send."] =
		"顯示伺服器是否接受了你送出的每一則訊息。",
	["Mark read when focused"] = "視窗移到前面時標為已讀",
	["Timestamps"] = "時間",
	["Reset all settings?"] = "重設全部設定？",
	["Every option goes back to its default. Message history is not touched."] =
		"所有選項都會回到預設值，訊息紀錄不受影響。",
	["Reset"] = "重設",
	["Enter a character name"] = "輸入角色名稱",
	["Name"] = "名稱",
	["Open"] = "開啟",
	["Whisper a player"] = "密語某位玩家",
	["Something went wrong repeatedly, so whispers are being shown in the chat frame again. /wtw debug for details."] =
		"接連出了問題，密語已改回顯示在聊天視窗中。詳情請用 /wtw debug。",
	["Whispers here cannot be read by addons, so they are being shown in the chat frame instead."] =
		"此處插件無法讀取密語，因此改在聊天視窗中顯示。",
	["Debug logging on."] = "除錯紀錄已開啟。",
	["Debug logging off."] = "除錯紀錄已關閉。",
	["/wtw show / hide - open or close the messenger"] = "/wtw show / hide - 開啟或關閉訊息視窗",
	["/wtw debug - toggle developer logging"] = "/wtw debug - 開關開發者紀錄",
	["/wtw reset - restore default settings"] = "/wtw reset - 還原預設設定",
	["WhatTheWhisper is ready. Type /wtw to open it."] =
		"WhatTheWhisper 已就緒，輸入 /wtw 即可開啟。",
	["Theme"] = "佈景主題",
	["Language"] = "語言",
	["Independent of the game's own language."] = "與遊戲本身的語言無關。",
	["Typography"] = "文字",
	["Show chat bubbles"] = "顯示對話框",
	["Delivery"] = "送達",
	["Mode"] = "模式",
	["Nothing logged yet."] = "還沒有任何紀錄。",
	["/wtw debug log - show the last few entries"] = "/wtw debug log - 顯示最近幾筆紀錄",
	["Open when you start a whisper"] = "開始密語時開啟",
	["Typing /w in the default chat box opens that conversation here."] =
		"在預設聊天視窗輸入 /w，就會在這裡開啟那段對話。",
})
