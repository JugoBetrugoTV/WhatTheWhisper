-- WhatTheWhisper -- 简体中文。
--
-- `true` 表示「与英文相同」，这是有意写下的：产品名称和文件格式名称不翻译，
-- 在这里写明白，才能区分「我们决定如此」和「有人漏了一行」。

local _, ns = ...

ns.RegisterLocale("zhCN", {
	-- 窗口
	["WhatTheWhisper"] = true,
	["Conversations"] = "会话",
	["Search conversations"] = "搜索会话",
	["Search messages"] = "搜索消息",
	["Character details"] = "角色资料",
	["Class, level, guild, zone and realm under the header."] =
		"在标题下方显示职业、等级、公会、区域和服务器。",
	["Class"] = "职业",
	["Race"] = "种族",
	["Guild"] = "公会",
	["Zone"] = "区域",
	["Realm"] = "服务器",
	["BattleTag"] = true,
	["Character"] = "角色",
	["not known"] = "未知",
	["Looking up..."] = "查询中……",
	["Try again in a moment"] = "请稍后再试",
	["New conversation"] = "新建会话",
	["Settings"] = "设置",
	["All windows"] = "所有窗口",
	["Show every open conversation window side by side."] =
		"把所有打开的会话窗口并排显示。",
	["Click a window to go to it, or press Escape"] =
		"点击窗口即可切换过去，按 Esc 退出",
	["Minimize"] = "最小化",
	["Close"] = "关闭",
	["Maximize"] = "最大化",
	["Restore"] = "还原",
	["Pop out"] = "独立窗口",
	["Dock"] = "停靠回去",
	["Pin"] = "置顶",
	["Unpin"] = "取消置顶",
	["Back"] = "返回",

	-- 输入
	["Message %s..."] = "发给 %s 的消息……",
	["Type a message..."] = "输入消息……",
	["Send"] = "发送",
	["Emoji"] = "表情",
	["%d characters over the limit"] = "超出 %d 个字符",
	["Will be sent as %d messages"] = "将分成 %d 条发送",

	-- 会话状态
	["Today"] = "今天",
	["Yesterday"] = "昨天",
	["Online"] = "在线",
	["Offline"] = "离线",
	["Away"] = "离开",
	["Busy"] = "忙碌",
	["Muted"] = "已静音",
	["Pinned"] = "已置顶",
	["You"] = "你",
	["Delivered"] = "已送达",
	["Sending"] = "发送中",
	["Not delivered"] = "未送达",
	["%s is not online"] = "%s 不在线",
	["There is no character named %s."] = "没有名为 %s 的角色。",
	["Character names are 2 to 12 letters, with no spaces, numbers or punctuation."] =
		"角色名为 2 到 12 个字母，不含空格、数字和标点。",
	["That realm name is not valid."] = "该服务器名称无效。",
	["A BattleTag looks like Name#1234."] = "战网标识的格式是 名字#1234。",
	["%d new messages"] = "%d 条新消息",
	["1 new message"] = "1 条新消息",
	["Level %d"] = "%d 级",
	["Battle.net"] = true,

	-- 空状态
	["No conversations yet"] = "还没有会话",
	["Whisper someone to start a conversation."] = "密语某人即可开始会话。",
	["Pick a conversation"] = "选一个会话",
	["Your whispers are kept here, one thread per player."] =
		"你的密语都保存在这里，每位玩家一条会话。",
	["No matches"] = "没有匹配项",
	["Try a different name or word."] = "换个名字或词试试。",
	["Start the conversation"] = "开始这段会话",
	["Say hi to %s."] = "跟 %s 打个招呼。",
	["History is off"] = "记录已关闭",
	["Enable it in Settings > History to keep messages."] =
		"在「设置 > 记录」中开启后才会保存消息。",
	["Nothing to show"] = "没有可显示的内容",

	-- 右键菜单
	["Whisper"] = "密语",
	["Invite to group"] = "邀请组队",
	["Add friend"] = "加为好友",
	["Ignore"] = "屏蔽",
	["Copy name"] = "复制名字",
	["Copy message"] = "复制消息",
	["Copy conversation"] = "复制会话",
	["Export conversation"] = "导出会话",
	["Clear history"] = "清空记录",
	["Mute conversation"] = "静音该会话",
	["Unmute conversation"] = "取消静音",
	["Pin conversation"] = "置顶该会话",
	["Unpin conversation"] = "取消置顶该会话",
	["Close conversation"] = "关闭该会话",
	["Target"] = "选中目标",
	["Look up"] = "查询",
	["Mark as read"] = "标为已读",
	["Mark as unread"] = "标为未读",
	["Copy URL"] = "复制链接",
	["Open in copy box"] = "在复制框中打开",

	-- 对话框
	["Copy"] = "复制",
	["Press Ctrl+C to copy, then Esc to close."] = "按 Ctrl+C 复制，再按 Esc 关闭。",
	["Press Ctrl+C to copy, or save it to a file."] = "按 Ctrl+C 复制，或保存为文件。",
	["Save to file"] = "保存为文件",
	["Saved. It is in %s after your next reload or logout."] =
		"已保存。重载界面或登出后可在 %s 找到。",
	["That conversation is too large to save."] = "该会话太大，无法保存。",
	["There was nothing to save."] = "没有可保存的内容。",
	["Export"] = "导出",
	["Format"] = "格式",
	["Plain text"] = "纯文本",
	["BBCode"] = true,
	["Markdown"] = true,
	["CSV"] = true,
	["Clear this conversation?"] = "清空这段会话？",
	["Clear all history?"] = "清空全部记录？",
	["This removes %d stored messages. It cannot be undone."] =
		"这会删除已保存的 %d 条消息，且无法撤销。",
	["This removes every stored message in %d conversations. It cannot be undone."] =
		"这会删除 %d 段会话中保存的全部消息，且无法撤销。",
	["Cancel"] = "取消",
	["Confirm"] = "确定",
	["Delete"] = "删除",

	-- 设置分类
	["General"] = "常规",
	["Appearance"] = "外观",
	["Messages"] = "消息",
	["History"] = "记录",
	["Sounds"] = "声音",
	["Notifications"] = "通知",
	["Animations"] = "动画",
	["Tabs"] = "标签页",
	["Windows"] = "窗口",
	["Combat"] = "战斗",
	["Links"] = "链接",
	["Emoticons"] = "表情符号",
	["Advanced"] = "高级",
	["Search settings"] = "搜索设置",
	["No settings match your search"] = "没有设置项匹配你的搜索",
	["Try a shorter word, or clear the search."] = "换个更短的词，或清空搜索。",
	["Nothing here yet"] = "这里还是空的",

	-- 设置：常规
	["Enable WhatTheWhisper"] = "启用 WhatTheWhisper",
	["Route whispers into the messenger instead of the default chat frame."] =
		"把密语导入信使窗口，而不是默认聊天框。",
	["Hide whispers from chat frames"] = "在聊天框中隐藏密语",
	["Whispers still arrive normally, they are just not printed in the chat window."] =
		"密语照常收到，只是不会打印在聊天窗口里。",
	["Open on new whisper"] = "收到新密语时打开",
	["Show the messenger automatically when someone whispers you."] =
		"有人密语你时自动显示信使窗口。",
	["Auto-switch to new conversations"] = "自动切换到新会话",
	["Switching away from what you are reading is off by default."] =
		"默认不会打断你正在读的内容。",
	["Minimap button"] = "小地图按钮",
	["Show a button on the minimap to toggle the messenger."] =
		"在小地图上显示一个按钮，用来开关信使窗口。",
	["Keep messenger open in combat"] = "战斗中保持信使窗口打开",

	-- 设置：外观
	["Skin"] = "皮肤",
	["Font"] = "字体",
	["Font size"] = "字号",
	["Background opacity"] = "背景不透明度",
	["Corner radius"] = "圆角半径",
	["Density"] = "疏密",
	["Comfortable"] = "宽松",
	["Compact"] = "紧凑",
	["Sidebar width"] = "侧栏宽度",
	["Use class colours"] = "使用职业颜色",
	["Show timestamps"] = "显示时间",
	["Timestamp format"] = "时间格式",
	["24 hour"] = "24 小时制",
	["12 hour"] = "12 小时制",
	["Show avatars"] = "显示头像",
	["Avatar style"] = "头像样式",
	["Automatic"] = "自动",
	["Class icon"] = "职业图标",
	["Initials"] = "名字首字",
	["Chat bubbles"] = "气泡",
	["Group messages"] = "合并消息",
	["Collapse consecutive messages from the same player."] =
		"把同一玩家连续发来的消息合并在一起。",
	["Show date separators"] = "显示日期分隔线",
	["Bubble opacity"] = "气泡不透明度",
	["Message spacing"] = "消息间距",

	-- 设置：布局
	["Layout"] = "布局",
	["Sidebar"] = "侧栏",
	["Tabbed"] = "标签页",
	["Hybrid"] = "混合",
	["Close tabs after"] = "多久后关闭标签页",
	["Never"] = "从不",
	["%d minutes"] = "%d 分钟",
	["Blink unread tabs"] = "未读标签页闪烁",
	["Open a tab for every conversation"] = "每段会话都开一个标签页",
	["Snap windows together"] = "窗口自动吸附",
	["Lock window position"] = "锁定窗口位置",
	["Remember window positions"] = "记住窗口位置",

	-- 设置：记录
	["Keep history"] = "保存记录",
	["Disabled"] = "关闭",
	["This session"] = "本次登录",
	["1 day"] = "1 天",
	["7 days"] = "7 天",
	["30 days"] = "30 天",
	["Unlimited"] = "不限",
	["Max messages per conversation"] = "每段会话最多消息数",
	["Max conversations"] = "最多会话数",
	["Stored messages: %d in %d conversations"] = "已保存 %d 条消息，共 %d 段会话",
	["Estimated size: %s"] = "估计占用：%s",
	["Clear all history"] = "清空全部记录",

	-- 设置：声音
	["Sound on new message"] = "新消息提示音",
	["Sound when window is hidden"] = "窗口隐藏时也提示",
	["Sound on mention"] = "被提到时提示音",
	["Sound when opening a conversation"] = "打开会话时提示音",
	["Repeat sound cooldown"] = "重复提示的间隔",
	["%d seconds"] = "%d 秒",
	["Do not disturb"] = "免打扰",
	["Silence everything until you turn this off."] = "在你关掉之前静音一切。",
	["Mute in combat"] = "战斗中静音",
	["Mute in dungeons"] = "地下城中静音",
	["Mute in raids"] = "团队副本中静音",
	["Mute in arenas"] = "竞技场中静音",
	["Mute in battlegrounds"] = "战场中静音",
	["None"] = "无",
	["Custom file"] = "自定义文件",
	["Sound file path"] = "声音文件路径",

	-- 设置：通知
	["Show toast notifications"] = "显示弹出通知",
	["Toast position"] = "通知位置",
	["Top right"] = "右上角",
	["Top left"] = "左上角",
	["Bottom right"] = "右下角",
	["Bottom left"] = "左下角",
	["Toast duration"] = "通知停留时间",
	["Flash taskbar icon"] = "闪烁任务栏图标",
	["Show unread badge"] = "显示未读数",
	["Summarise repeated messages"] = "合并重复的消息",

	-- 设置：动画
	["Animation level"] = "动画程度",
	["Off"] = "关闭",
	["Reduced"] = "精简",
	["Normal"] = "正常",
	["Fancy"] = "华丽",
	["Smooth scrolling"] = "平滑滚动",

	-- 设置：战斗
	["Entering combat"] = "进入战斗时",
	["Do nothing"] = "什么也不做",
	["Fade conversations"] = "淡化会话窗口",
	["Minimize conversations"] = "最小化会话窗口",
	["Hide conversations"] = "隐藏会话窗口",
	["Leaving combat"] = "脱离战斗时",
	["Restore previous state"] = "恢复原状",
	["Stay hidden"] = "保持隐藏",
	["Combat fade opacity"] = "战斗中的不透明度",

	-- 设置：链接与表情符号
	["Detect links"] = "识别链接",
	["Highlight links in messages and make them clickable."] =
		"高亮消息中的链接，并让它可以点击。",
	["Link colour"] = "链接颜色",
	["Emoticon style"] = "表情符号样式",
	["Text"] = "文字",
	["Coloured text"] = "彩色文字",
	["Images"] = "图片",
	["Convert raid target markers"] = "把团队标记转成图标",

	-- 设置：高级
	["Debug messages"] = "调试信息",
	["Reset everything"] = "全部重置",
	["Profile"] = "配置文件",
	["Diagnostics"] = "诊断",
	["Client"] = "客户端",
	["Reset window positions"] = "重置窗口位置",

	-- 表情选择
	["Smileys"] = "笑脸",
	["Symbols"] = "符号",
	["Markers"] = "团队标记",
	["Recent"] = "最近",

	-- 提示
	["%s is offline. Message not delivered."] = "%s 不在线，消息未送达。",
	["Message too long, sent as %d parts."] = "消息过长，已分成 %d 条发送。",

	-- 命令帮助
	["Commands:"] = "命令：",
	["/wtw - toggle the messenger"] = "/wtw - 开关信使窗口",
	["Right-click for the list"] = "右键点击查看列表",
	["Mark all as read"] = "全部标为已读",
	["Hide minimap button"] = "隐藏小地图按钮",
	["/wtw config - open settings"] = "/wtw config - 打开设置",
	["/wtw <name> - open a conversation"] = "/wtw <名字> - 打开会话",
	["/wtw clear - clear all history"] = "/wtw clear - 清空全部记录",
	["/wtw diag - print client diagnostics"] = "/wtw diag - 输出客户端诊断信息",

	-- 随设置结构一同加入的文字
	["Drop shadows"] = "投影",
	["Square"] = "直角",
	["Round"] = "圆角",
	["Always"] = "始终",
	["Timestamp on hover"] = "鼠标悬停时显示时间",
	["Maximum toasts"] = "同时显示的通知数",
	["Show delivery state"] = "显示送达状态",
	["Show whether the server accepted each message you send."] =
		"显示服务器是否接受了你发出的每条消息。",
	["Mark read when focused"] = "窗口置前时标为已读",
	["Timestamps"] = "时间",
	["Reset all settings?"] = "重置全部设置？",
	["Every option goes back to its default. Message history is not touched."] =
		"所有选项恢复默认值，消息记录不受影响。",
	["Reset"] = "重置",
	["Enter a character name"] = "输入角色名",
	["Name"] = "名字",
	["Open"] = "打开",
	["Whisper a player"] = "密语某位玩家",
	["Something went wrong repeatedly, so whispers are being shown in the chat frame again. /wtw debug for details."] =
		"多次出错，密语已改回显示在聊天框中。详情请用 /wtw debug。",
	["Whispers here cannot be read by addons, so they are being shown in the chat frame instead."] =
		"此处插件无法读取密语，因此改在聊天框中显示。",
	["Debug logging on."] = "调试日志已开启。",
	["Debug logging off."] = "调试日志已关闭。",
	["/wtw show / hide - open or close the messenger"] = "/wtw show / hide - 打开或关闭信使窗口",
	["/wtw debug - toggle developer logging"] = "/wtw debug - 开关开发日志",
	["/wtw reset - restore default settings"] = "/wtw reset - 恢复默认设置",
	["WhatTheWhisper is ready. Type /wtw to open it."] =
		"WhatTheWhisper 已就绪，输入 /wtw 打开。",
	["Theme"] = "主题",
	["Language"] = "语言",
	["Independent of the game's own language."] = "与游戏本身的语言无关。",
	["Typography"] = "文字",
	["Show chat bubbles"] = "显示气泡",
	["Delivery"] = "送达",
	["Mode"] = "模式",
	["Nothing logged yet."] = "还没有日志。",
	["/wtw debug log - show the last few entries"] = "/wtw debug log - 显示最近几条日志",
	["Open when you start a whisper"] = "开始密语时打开",
	["Typing /w in the default chat box opens that conversation here."] =
		"在默认聊天框里输入 /w，会在这里打开那段会话。",
})
