-- WhatTheWhisper -- 한국어.
--
-- `true`는 "영어 그대로"라는 뜻이며, 일부러 적어 둔 것입니다. 제품 이름이나
-- 파일 형식 이름은 번역하지 않으며, 그 사실을 여기에 적어 두는 것이 "그렇게
-- 정했다"와 "누가 한 줄을 빠뜨렸다"의 차이입니다.

local _, ns = ...

ns.RegisterLocale("koKR", {
	-- 창
	["WhatTheWhisper"] = true,
	["Conversations"] = "대화",
	["Search conversations"] = "대화 검색",
	["Search messages"] = "메시지 검색",
	["Character details"] = "캐릭터 정보",
	["Class, level, guild, zone and realm under the header."] =
		"이름 아래에 직업, 레벨, 길드, 지역, 서버를 표시합니다.",
	["Class"] = "직업",
	["Race"] = "종족",
	["Guild"] = "길드",
	["Zone"] = "지역",
	["Realm"] = "서버",
	["BattleTag"] = true,
	["Character"] = "캐릭터",
	["not known"] = "알 수 없음",
	["Looking up..."] = "조회 중...",
	["Try again in a moment"] = "잠시 후 다시 시도하세요",
	["New conversation"] = "새 대화",
	["Settings"] = "설정",
	["All windows"] = "모든 창",
	["Show every open conversation window side by side."] =
		"열려 있는 대화 창을 모두 나란히 보여 줍니다.",
	["Click a window to go to it, or press Escape"] =
		"창을 클릭하면 그곳으로 이동하고, Esc를 누르면 닫힙니다",
	["Minimize"] = "최소화",
	["Close"] = "닫기",
	["Maximize"] = "최대화",
	["Restore"] = "이전 크기로",
	["Pop out"] = "떼어내기",
	["Dock"] = "붙이기",
	["Pin"] = "고정",
	["Unpin"] = "고정 해제",
	["Back"] = "뒤로",

	-- 작성
	["Message %s..."] = "%s님에게 보낼 메시지...",
	["Type a message..."] = "메시지를 입력하세요...",
	["Send"] = "보내기",
	["Emoji"] = "이모지",
	["%d characters over the limit"] = "%d자 초과",
	["Will be sent as %d messages"] = "%d개의 메시지로 나뉘어 전송됩니다",

	-- 대화 상태
	["Today"] = "오늘",
	["Yesterday"] = "어제",
	["Online"] = "접속 중",
	["Offline"] = "미접속",
	["Away"] = "자리 비움",
	["Busy"] = "다른 용무 중",
	["Muted"] = "알림 끔",
	["Pinned"] = "고정됨",
	["You"] = "나",
	["Delivered"] = "전달됨",
	["Sending"] = "보내는 중",
	["Not delivered"] = "전달되지 않음",
	["%s is not online"] = "%s님은 접속해 있지 않습니다",
	["There is no character named %s."] = "%s(이)라는 캐릭터가 없습니다.",
	["Character names are 2 to 12 letters, with no spaces, numbers or punctuation."] =
		"캐릭터 이름은 공백, 숫자, 문장 부호 없이 2~12자입니다.",
	["That realm name is not valid."] = "올바른 서버 이름이 아닙니다.",
	["A BattleTag looks like Name#1234."] = "배틀태그는 이름#1234 형식입니다.",
	["%d new messages"] = "새 메시지 %d개",
	["1 new message"] = "새 메시지 1개",
	["Level %d"] = "%d레벨",
	["Battle.net"] = true,

	-- 비어 있을 때
	["No conversations yet"] = "아직 대화가 없습니다",
	["Whisper someone to start a conversation."] =
		"누군가에게 귓속말을 보내면 대화가 시작됩니다.",
	["Pick a conversation"] = "대화를 고르세요",
	["Your whispers are kept here, one thread per player."] =
		"귓속말은 여기에 보관되며, 플레이어마다 대화 하나입니다.",
	["No matches"] = "결과 없음",
	["Try a different name or word."] = "다른 이름이나 단어로 찾아보세요.",
	["Start the conversation"] = "대화를 시작하세요",
	["Say hi to %s."] = "%s님에게 인사를 건네 보세요.",
	["History is off"] = "기록이 꺼져 있습니다",
	["Enable it in Settings > History to keep messages."] =
		"메시지를 보관하려면 설정 > 기록에서 켜세요.",
	["Nothing to show"] = "표시할 내용이 없습니다",

	-- 오른쪽 클릭 메뉴
	["Whisper"] = "귓속말",
	["Invite to group"] = "파티 초대",
	["Add friend"] = "친구 추가",
	["Ignore"] = "무시",
	["Copy name"] = "이름 복사",
	["Copy message"] = "메시지 복사",
	["Copy conversation"] = "대화 복사",
	["Export conversation"] = "대화 내보내기",
	["Clear history"] = "기록 지우기",
	["Mute conversation"] = "대화 알림 끄기",
	["Unmute conversation"] = "대화 알림 켜기",
	["Pin conversation"] = "대화 고정",
	["Unpin conversation"] = "대화 고정 해제",
	["Close conversation"] = "대화 닫기",
	["Target"] = "대상 지정",
	["Look up"] = "조회",
	["Mark as read"] = "읽음으로 표시",
	["Mark as unread"] = "읽지 않음으로 표시",
	["Copy URL"] = "주소 복사",
	["Open in copy box"] = "복사 창에서 열기",

	-- 대화 상자
	["Copy"] = "복사",
	["Press Ctrl+C to copy, then Esc to close."] =
		"Ctrl+C로 복사한 뒤 Esc로 닫으세요.",
	["Press Ctrl+C to copy, or save it to a file."] =
		"Ctrl+C로 복사하거나 파일로 저장하세요.",
	["Save to file"] = "파일로 저장",
	["Saved. It is in %s after your next reload or logout."] =
		"저장했습니다. 인터페이스를 다시 불러오거나 접속을 종료하면 %s에 생깁니다.",
	["That conversation is too large to save."] =
		"이 대화는 너무 커서 저장할 수 없습니다.",
	["There was nothing to save."] = "저장할 내용이 없었습니다.",
	["Export"] = "내보내기",
	["Format"] = "형식",
	["Plain text"] = "일반 텍스트",
	["BBCode"] = true,
	["Markdown"] = true,
	["CSV"] = true,
	["Clear this conversation?"] = "이 대화를 지울까요?",
	["Clear all history?"] = "모든 기록을 지울까요?",
	["This removes %d stored messages. It cannot be undone."] =
		"저장된 메시지 %d개가 지워집니다. 되돌릴 수 없습니다.",
	["This removes every stored message in %d conversations. It cannot be undone."] =
		"대화 %d개에 저장된 모든 메시지가 지워집니다. 되돌릴 수 없습니다.",
	["Cancel"] = "취소",
	["Confirm"] = "확인",
	["Delete"] = "삭제",

	-- 설정 분류
	["General"] = "일반",
	["Appearance"] = "모양",
	["Messages"] = "메시지",
	["History"] = "기록",
	["Sounds"] = "소리",
	["Notifications"] = "알림",
	["Animations"] = "애니메이션",
	["Tabs"] = "탭",
	["Windows"] = "창",
	["Combat"] = "전투",
	["Links"] = "링크",
	["Emoticons"] = "이모티콘",
	["Advanced"] = "고급",
	["Search settings"] = "설정 검색",
	["No settings match your search"] = "검색과 일치하는 설정이 없습니다",
	["Try a shorter word, or clear the search."] =
		"더 짧은 단어로 찾거나 검색어를 지우세요.",
	["Nothing here yet"] = "아직 아무것도 없습니다",

	-- 설정: 일반
	["Enable WhatTheWhisper"] = "WhatTheWhisper 사용",
	["Route whispers into the messenger instead of the default chat frame."] =
		"귓속말을 기본 대화창 대신 메신저로 보냅니다.",
	["Hide whispers from chat frames"] = "대화창에서 귓속말 숨기기",
	["Whispers still arrive normally, they are just not printed in the chat window."] =
		"귓속말은 그대로 도착하며, 대화창에 표시되지 않을 뿐입니다.",
	["Open on new whisper"] = "새 귓속말이 오면 열기",
	["Show the messenger automatically when someone whispers you."] =
		"누군가 귓속말을 보내면 메신저를 저절로 엽니다.",
	["Auto-switch to new conversations"] = "새 대화로 자동 전환",
	["Switching away from what you are reading is off by default."] =
		"읽고 있던 대화에서 벗어나는 동작은 기본으로 꺼져 있습니다.",
	["Minimap button"] = "미니맵 단추",
	["Show a button on the minimap to toggle the messenger."] =
		"메신저를 여닫는 단추를 미니맵에 표시합니다.",
	["Keep messenger open in combat"] = "전투 중에도 메신저 열어 두기",

	-- 설정: 모양
	["Skin"] = "스킨",
	["Font"] = "글꼴",
	["Font size"] = "글꼴 크기",
	["Background opacity"] = "배경 불투명도",
	["Corner radius"] = "모서리 둥글기",
	["Density"] = "간격",
	["Comfortable"] = "넉넉하게",
	["Compact"] = "빽빽하게",
	["Sidebar width"] = "옆 목록 너비",
	["Use class colours"] = "직업 색 사용",
	["Show timestamps"] = "시각 표시",
	["Timestamp format"] = "시각 형식",
	["24 hour"] = "24시간",
	["12 hour"] = "12시간",
	["Show avatars"] = "아이콘 표시",
	["Avatar style"] = "아이콘 모양",
	["Automatic"] = "자동",
	["Class icon"] = "직업 아이콘",
	["Initials"] = "이름 첫 글자",
	["Chat bubbles"] = "말풍선",
	["Group messages"] = "메시지 묶기",
	["Collapse consecutive messages from the same player."] =
		"같은 플레이어가 잇달아 보낸 메시지를 하나로 묶습니다.",
	["Show date separators"] = "날짜 구분선 표시",
	["Bubble opacity"] = "말풍선 불투명도",
	["Message spacing"] = "메시지 간격",

	-- 설정: 배치
	["Layout"] = "배치",
	["Sidebar"] = "옆 목록",
	["Tabbed"] = "탭",
	["Hybrid"] = "혼합",
	["Close tabs after"] = "탭 닫기 대기 시간",
	["Never"] = "안 함",
	["%d minutes"] = "%d분",
	["Blink unread tabs"] = "읽지 않은 탭 깜박이기",
	["Open a tab for every conversation"] = "대화마다 탭 열기",
	["Snap windows together"] = "창끼리 붙이기",
	["Lock window position"] = "창 위치 고정",
	["Remember window positions"] = "창 위치 기억",

	-- 설정: 기록
	["Keep history"] = "기록 보관",
	["Disabled"] = "사용 안 함",
	["This session"] = "이번 접속 동안",
	["1 day"] = "1일",
	["7 days"] = "7일",
	["30 days"] = "30일",
	["Unlimited"] = "제한 없음",
	["Max messages per conversation"] = "대화당 최대 메시지",
	["Max conversations"] = "최대 대화 수",
	["Stored messages: %d in %d conversations"] =
		"저장된 메시지 %d개, 대화 %d개",
	["Estimated size: %s"] = "예상 크기: %s",
	["Clear all history"] = "모든 기록 지우기",

	-- 설정: 소리
	["Sound on new message"] = "새 메시지 소리",
	["Sound when window is hidden"] = "창이 숨겨져 있을 때 소리",
	["Sound on mention"] = "내 이름이 불릴 때 소리",
	["Sound when opening a conversation"] = "대화를 열 때 소리",
	["Repeat sound cooldown"] = "소리 반복 간격",
	["%d seconds"] = "%d초",
	["Do not disturb"] = "방해 금지",
	["Silence everything until you turn this off."] =
		"끄기 전까지 모든 소리를 멈춥니다.",
	["Mute in combat"] = "전투 중 소리 끄기",
	["Mute in dungeons"] = "던전에서 소리 끄기",
	["Mute in raids"] = "공격대 던전에서 소리 끄기",
	["Mute in arenas"] = "투기장에서 소리 끄기",
	["Mute in battlegrounds"] = "전장에서 소리 끄기",
	["None"] = "없음",
	["Custom file"] = "직접 지정한 파일",
	["Sound file path"] = "소리 파일 경로",

	-- 설정: 알림
	["Show toast notifications"] = "알림 띄우기",
	["Toast position"] = "알림 위치",
	["Top right"] = "오른쪽 위",
	["Top left"] = "왼쪽 위",
	["Bottom right"] = "오른쪽 아래",
	["Bottom left"] = "왼쪽 아래",
	["Toast duration"] = "알림 표시 시간",
	["Flash taskbar icon"] = "작업 표시줄 아이콘 깜박이기",
	["Show unread badge"] = "읽지 않은 개수 표시",
	["Summarise repeated messages"] = "반복된 메시지 요약",

	-- 설정: 애니메이션
	["Animation level"] = "애니메이션 정도",
	["Off"] = "끔",
	["Reduced"] = "줄임",
	["Normal"] = "보통",
	["Fancy"] = "화려하게",
	["Smooth scrolling"] = "부드러운 스크롤",

	-- 설정: 전투
	["Entering combat"] = "전투에 들어갈 때",
	["Do nothing"] = "아무것도 하지 않기",
	["Fade conversations"] = "대화 흐리게",
	["Minimize conversations"] = "대화 최소화",
	["Hide conversations"] = "대화 숨기기",
	["Leaving combat"] = "전투가 끝날 때",
	["Restore previous state"] = "이전 상태로 되돌리기",
	["Stay hidden"] = "계속 숨김",
	["Combat fade opacity"] = "전투 중 불투명도",

	-- 설정: 링크와 이모티콘
	["Detect links"] = "링크 인식",
	["Highlight links in messages and make them clickable."] =
		"메시지 속 링크를 눈에 띄게 하고 클릭할 수 있게 합니다.",
	["Link colour"] = "링크 색",
	["Emoticon style"] = "이모티콘 모양",
	["Text"] = "글자",
	["Coloured text"] = "색이 있는 글자",
	["Images"] = "그림",
	["Convert raid target markers"] = "공격 표시를 아이콘으로 바꾸기",

	-- 설정: 고급
	["Debug messages"] = "디버그 메시지",
	["Reset everything"] = "모두 초기화",
	["Profile"] = "프로필",
	["Diagnostics"] = "진단",
	["Client"] = "클라이언트",
	["Reset window positions"] = "창 위치 초기화",

	-- 이모지 고르기
	["Smileys"] = "표정",
	["Symbols"] = "기호",
	["Markers"] = "공격 표시",
	["Recent"] = "최근",

	-- 알림
	["%s is offline. Message not delivered."] =
		"%s님은 접속해 있지 않습니다. 메시지가 전달되지 않았습니다.",
	["Message too long, sent as %d parts."] =
		"메시지가 너무 길어 %d개로 나눠 보냈습니다.",

	-- 명령어 도움말
	["Commands:"] = "명령어:",
	["/wtw - toggle the messenger"] = "/wtw - 메신저 열기/닫기",
	["Right-click for the list"] = "오른쪽 클릭하면 목록이 나옵니다",
	["Mark all as read"] = "모두 읽음으로 표시",
	["Hide minimap button"] = "미니맵 단추 숨기기",
	["/wtw config - open settings"] = "/wtw config - 설정 열기",
	["/wtw <name> - open a conversation"] = "/wtw <이름> - 대화 열기",
	["/wtw clear - clear all history"] = "/wtw clear - 모든 기록 지우기",
	["/wtw diag - print client diagnostics"] = "/wtw diag - 클라이언트 진단 출력",

	-- 설정 구조와 함께 추가된 표시 문구
	["Drop shadows"] = "그림자",
	["Square"] = "각지게",
	["Round"] = "둥글게",
	["Always"] = "항상",
	["Timestamp on hover"] = "마우스를 올리면 시각 표시",
	["Maximum toasts"] = "한 번에 띄울 알림 수",
	["Show delivery state"] = "전달 상태 표시",
	["Show whether the server accepted each message you send."] =
		"보낸 메시지를 서버가 받아들였는지 보여 줍니다.",
	["Mark read when focused"] = "창을 앞으로 가져오면 읽음 처리",
	["Timestamps"] = "시각",
	["Reset all settings?"] = "모든 설정을 초기화할까요?",
	["Every option goes back to its default. Message history is not touched."] =
		"모든 항목이 처음 값으로 돌아갑니다. 메시지 기록은 그대로입니다.",
	["Reset"] = "초기화",
	["Enter a character name"] = "캐릭터 이름을 입력하세요",
	["Name"] = "이름",
	["Open"] = "열기",
	["Whisper a player"] = "플레이어에게 귓속말",
	["Something went wrong repeatedly, so whispers are being shown in the chat frame again. /wtw debug for details."] =
		"문제가 거듭 일어나서 귓속말을 다시 대화창에 표시합니다. 자세한 내용은 /wtw debug.",
	["Whispers here cannot be read by addons, so they are being shown in the chat frame instead."] =
		"이곳에서는 애드온이 귓속말을 읽을 수 없어서 대화창에 표시합니다.",
	["Debug logging on."] = "디버그 기록을 켰습니다.",
	["Debug logging off."] = "디버그 기록을 껐습니다.",
	["/wtw show / hide - open or close the messenger"] =
		"/wtw show / hide - 메신저 열기 또는 닫기",
	["/wtw debug - toggle developer logging"] = "/wtw debug - 개발용 기록 켜기/끄기",
	["/wtw reset - restore default settings"] = "/wtw reset - 기본 설정으로 되돌리기",
	["WhatTheWhisper is ready. Type /wtw to open it."] =
		"WhatTheWhisper 준비 완료. /wtw를 입력하면 열립니다.",
	["Theme"] = "테마",
	["Language"] = "언어",
	["Independent of the game's own language."] = "게임 언어와 상관없이 정할 수 있습니다.",
	["Typography"] = "글자",
	["Show chat bubbles"] = "말풍선 표시",
	["Delivery"] = "전달",
	["Mode"] = "방식",
	["Nothing logged yet."] = "아직 기록이 없습니다.",
	["/wtw debug log - show the last few entries"] = "/wtw debug log - 최근 기록 보기",
	["Open when you start a whisper"] = "귓속말을 시작할 때 열기",
	["Typing /w in the default chat box opens that conversation here."] =
		"기본 대화창에 /w를 입력하면 그 대화가 여기에서 열립니다.",
})
