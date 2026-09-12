-- WhatTheWhisper -- Русский.
--
-- `true` означает «так же, как по-английски», и это написано намеренно: имя
-- продукта или название формата не переводят, а сказать об этом здесь -- разница
-- между «мы так решили» и «кто-то забыл строку».

local _, ns = ...

ns.RegisterLocale("ruRU", {
	-- Окно
	["WhatTheWhisper"] = true,
	["Conversations"] = "Разговоры",
	["Search conversations"] = "Поиск по разговорам",
	["Search messages"] = "Поиск по сообщениям",
	["Character details"] = "Сведения о персонаже",
	["Class, level, guild, zone and realm under the header."] =
		"Класс, уровень, гильдия, зона и игровой мир под заголовком.",
	["Class"] = "Класс",
	["Race"] = "Раса",
	["Guild"] = "Гильдия",
	["Zone"] = "Зона",
	["Realm"] = "Игровой мир",
	["BattleTag"] = true,
	["Character"] = "Персонаж",
	["not known"] = "неизвестно",
	["Looking up..."] = "Запрашиваем...",
	["Try again in a moment"] = "Повторите через мгновение",
	["New conversation"] = "Новый разговор",
	["Settings"] = "Настройки",
	["All windows"] = "Все окна",
	["Show every open conversation window side by side."] =
		"Показывает все открытые окна разговоров рядом друг с другом.",
	["Click a window to go to it, or press Escape"] =
		"Щёлкните по окну, чтобы перейти к нему, или нажмите Esc",
	["Minimize"] = "Свернуть",
	["Close"] = "Закрыть",
	["Maximize"] = "Развернуть",
	["Restore"] = "Восстановить",
	["Pop out"] = "Отделить",
	["Dock"] = "Присоединить",
	["Pin"] = "Закрепить",
	["Unpin"] = "Открепить",
	["Back"] = "Назад",

	-- Написание сообщения
	["Message %s..."] = "Сообщение для %s...",
	["Type a message..."] = "Напишите сообщение...",
	["Send"] = "Отправить",
	["Emoji"] = "Эмодзи",
	["%d characters over the limit"] = "Лишних символов: %d",
	["Will be sent as %d messages"] = "Будет отправлено %d сообщениями",

	-- Состояние разговоров
	["Today"] = "Сегодня",
	["Yesterday"] = "Вчера",
	["Online"] = "В сети",
	["Offline"] = "Не в сети",
	["Away"] = "Отошёл",
	["Busy"] = "Занят",
	["Muted"] = "Без звука",
	["Pinned"] = "Закреплён",
	["You"] = "Вы",
	["Delivered"] = "Доставлено",
	["Sending"] = "Отправляется",
	["Not delivered"] = "Не доставлено",
	["%s is not online"] = "%s не в сети",
	["There is no character named %s."] = "Персонажа с именем %s не существует.",
	["Character names are 2 to 12 letters, with no spaces, numbers or punctuation."] =
		"Имя персонажа -- от 2 до 12 букв, без пробелов, цифр и знаков препинания.",
	["That realm name is not valid."] = "Такое название игрового мира недопустимо.",
	["A BattleTag looks like Name#1234."] = "BattleTag выглядит так: Имя#1234.",
	["%d new messages"] = "Новых сообщений: %d",
	["1 new message"] = "1 новое сообщение",
	["Level %d"] = "Уровень %d",
	["Battle.net"] = true,

	-- Пустые состояния
	["No conversations yet"] = "Разговоров пока нет",
	["Whisper someone to start a conversation."] =
		"Шепните кому-нибудь, чтобы начать разговор.",
	["Pick a conversation"] = "Выберите разговор",
	["Your whispers are kept here, one thread per player."] =
		"Ваш шёпот хранится здесь, по одной ветке на игрока.",
	["No matches"] = "Ничего не найдено",
	["Try a different name or word."] = "Попробуйте другое имя или слово.",
	["Start the conversation"] = "Начните разговор",
	["Say hi to %s."] = "Поздоровайтесь с %s.",
	["History is off"] = "История выключена",
	["Enable it in Settings > History to keep messages."] =
		"Включите её в «Настройки > История», чтобы сообщения сохранялись.",
	["Nothing to show"] = "Показывать нечего",

	-- Контекстное меню
	["Whisper"] = "Шепнуть",
	["Invite to group"] = "Пригласить в группу",
	["Add friend"] = "Добавить в друзья",
	["Ignore"] = "Игнорировать",
	["Copy name"] = "Копировать имя",
	["Copy message"] = "Копировать сообщение",
	["Copy conversation"] = "Копировать разговор",
	["Export conversation"] = "Экспортировать разговор",
	["Clear history"] = "Очистить историю",
	["Mute conversation"] = "Отключить звук разговора",
	["Unmute conversation"] = "Включить звук разговора",
	["Pin conversation"] = "Закрепить разговор",
	["Unpin conversation"] = "Открепить разговор",
	["Close conversation"] = "Закрыть разговор",
	["Target"] = "Взять в цель",
	["Look up"] = "Запросить",
	["Mark as read"] = "Отметить прочитанным",
	["Mark as unread"] = "Отметить непрочитанным",
	["Copy URL"] = "Копировать ссылку",
	["Open in copy box"] = "Открыть в окне копирования",

	-- Диалоги
	["Copy"] = "Копировать",
	["Press Ctrl+C to copy, then Esc to close."] =
		"Нажмите Ctrl+C, чтобы скопировать, затем Esc, чтобы закрыть.",
	["Press Ctrl+C to copy, or save it to a file."] =
		"Нажмите Ctrl+C, чтобы скопировать, или сохраните в файл.",
	["Save to file"] = "Сохранить в файл",
	["Saved. It is in %s after your next reload or logout."] =
		"Сохранено. Файл появится в %s после перезагрузки интерфейса или выхода.",
	["That conversation is too large to save."] =
		"Этот разговор слишком велик, чтобы его сохранить.",
	["There was nothing to save."] = "Сохранять было нечего.",
	["Export"] = "Экспорт",
	["Format"] = "Формат",
	["Plain text"] = "Обычный текст",
	["BBCode"] = true,
	["Markdown"] = true,
	["CSV"] = true,
	["Clear this conversation?"] = "Очистить этот разговор?",
	["Clear all history?"] = "Очистить всю историю?",
	["This removes %d stored messages. It cannot be undone."] =
		"Будет удалено сохранённых сообщений: %d. Отменить это нельзя.",
	["This removes every stored message in %d conversations. It cannot be undone."] =
		"Будут удалены все сохранённые сообщения в %d разговорах. Отменить это нельзя.",
	["Cancel"] = "Отмена",
	["Confirm"] = "Подтвердить",
	["Delete"] = "Удалить",

	-- Разделы настроек
	["General"] = "Общие",
	["Appearance"] = "Внешний вид",
	["Messages"] = "Сообщения",
	["History"] = "История",
	["Sounds"] = "Звуки",
	["Notifications"] = "Уведомления",
	["Animations"] = "Анимация",
	["Tabs"] = "Вкладки",
	["Windows"] = "Окна",
	["Combat"] = "Бой",
	["Links"] = "Ссылки",
	["Emoticons"] = "Смайлики",
	["Advanced"] = "Дополнительно",
	["Search settings"] = "Поиск по настройкам",
	["No settings match your search"] = "Ни одна настройка не подходит под запрос",
	["Try a shorter word, or clear the search."] =
		"Попробуйте слово покороче или очистите поиск.",
	["Nothing here yet"] = "Здесь пока пусто",

	-- Настройки: общие
	["Enable WhatTheWhisper"] = "Включить WhatTheWhisper",
	["Route whispers into the messenger instead of the default chat frame."] =
		"Направляет шёпот в мессенджер вместо обычного окна чата.",
	["Hide whispers from chat frames"] = "Скрывать шёпот в окнах чата",
	["Whispers still arrive normally, they are just not printed in the chat window."] =
		"Шёпот по-прежнему приходит как обычно, просто он не выводится в окне чата.",
	["Open on new whisper"] = "Открывать при новом шёпоте",
	["Show the messenger automatically when someone whispers you."] =
		"Показывает мессенджер сам, когда вам кто-то шепчет.",
	["Auto-switch to new conversations"] = "Самому переключаться на новые разговоры",
	["Switching away from what you are reading is off by default."] =
		"Уход от того, что вы читаете, по умолчанию выключен.",
	["Minimap button"] = "Кнопка у миникарты",
	["Show a button on the minimap to toggle the messenger."] =
		"Показывает у миникарты кнопку, открывающую и закрывающую мессенджер.",
	["Keep messenger open in combat"] = "Не закрывать мессенджер в бою",

	-- Настройки: внешний вид
	["Skin"] = "Оформление",
	["Font"] = "Шрифт",
	["Font size"] = "Размер шрифта",
	["Background opacity"] = "Непрозрачность фона",
	["Corner radius"] = "Скругление углов",
	["Density"] = "Плотность",
	["Comfortable"] = "Свободная",
	["Compact"] = "Плотная",
	["Sidebar width"] = "Ширина боковой панели",
	["Use class colours"] = "Цвета классов",
	["Show timestamps"] = "Показывать время",
	["Timestamp format"] = "Формат времени",
	["24 hour"] = "24 часа",
	["12 hour"] = "12 часов",
	["Show avatars"] = "Показывать аватары",
	["Avatar style"] = "Вид аватара",
	["Automatic"] = "Автоматически",
	["Class icon"] = "Значок класса",
	["Initials"] = "Инициалы",
	["Chat bubbles"] = "Облачка сообщений",
	["Group messages"] = "Группировать сообщения",
	["Collapse consecutive messages from the same player."] =
		"Объединяет идущие подряд сообщения одного игрока.",
	["Show date separators"] = "Показывать разделители по датам",
	["Bubble opacity"] = "Непрозрачность облачек",
	["Message spacing"] = "Расстояние между сообщениями",

	-- Настройки: расположение
	["Layout"] = "Расположение",
	["Sidebar"] = "Боковая панель",
	["Tabbed"] = "Вкладками",
	["Hybrid"] = "Смешанное",
	["Close tabs after"] = "Закрывать вкладки через",
	["Never"] = "Никогда",
	["%d minutes"] = "%d мин.",
	["Blink unread tabs"] = "Мигание непрочитанных вкладок",
	["Open a tab for every conversation"] = "Открывать вкладку для каждого разговора",
	["Snap windows together"] = "Прилипание окон друг к другу",
	["Lock window position"] = "Закрепить положение окна",
	["Remember window positions"] = "Запоминать положение окон",

	-- Настройки: история
	["Keep history"] = "Хранить историю",
	["Disabled"] = "Выключено",
	["This session"] = "Этот сеанс",
	["1 day"] = "1 день",
	["7 days"] = "7 дней",
	["30 days"] = "30 дней",
	["Unlimited"] = "Без ограничения",
	["Max messages per conversation"] = "Макс. сообщений в разговоре",
	["Max conversations"] = "Макс. разговоров",
	["Stored messages: %d in %d conversations"] =
		"Сохранено сообщений: %d в %d разговорах",
	["Estimated size: %s"] = "Примерный объём: %s",
	["Clear all history"] = "Очистить всю историю",

	-- Настройки: звуки
	["Sound on new message"] = "Звук при новом сообщении",
	["Sound when window is hidden"] = "Звук, когда окно скрыто",
	["Sound on mention"] = "Звук при упоминании",
	["Sound when opening a conversation"] = "Звук при открытии разговора",
	["Repeat sound cooldown"] = "Пауза между повторами звука",
	["%d seconds"] = "%d сек.",
	["Do not disturb"] = "Не беспокоить",
	["Silence everything until you turn this off."] =
		"Полная тишина, пока вы это не выключите.",
	["Mute in combat"] = "Без звука в бою",
	["Mute in dungeons"] = "Без звука в подземельях",
	["Mute in raids"] = "Без звука в рейдах",
	["Mute in arenas"] = "Без звука на аренах",
	["Mute in battlegrounds"] = "Без звука на полях боя",
	["None"] = "Нет",
	["Custom file"] = "Свой файл",
	["Sound file path"] = "Путь к звуковому файлу",

	-- Настройки: уведомления
	["Show toast notifications"] = "Показывать всплывающие уведомления",
	["Toast position"] = "Положение уведомлений",
	["Top right"] = "Сверху справа",
	["Top left"] = "Сверху слева",
	["Bottom right"] = "Снизу справа",
	["Bottom left"] = "Снизу слева",
	["Toast duration"] = "Длительность уведомлений",
	["Flash taskbar icon"] = "Мигать значком на панели задач",
	["Show unread badge"] = "Показывать счётчик непрочитанных",
	["Summarise repeated messages"] = "Сворачивать повторяющиеся сообщения",

	-- Настройки: анимация
	["Animation level"] = "Уровень анимации",
	["Off"] = "Выключена",
	["Reduced"] = "Пониженная",
	["Normal"] = "Обычная",
	["Fancy"] = "Богатая",
	["Smooth scrolling"] = "Плавная прокрутка",

	-- Настройки: бой
	["Entering combat"] = "При входе в бой",
	["Do nothing"] = "Ничего не делать",
	["Fade conversations"] = "Приглушать разговоры",
	["Minimize conversations"] = "Сворачивать разговоры",
	["Hide conversations"] = "Скрывать разговоры",
	["Leaving combat"] = "При выходе из боя",
	["Restore previous state"] = "Вернуть как было",
	["Stay hidden"] = "Оставить скрытым",
	["Combat fade opacity"] = "Непрозрачность в бою",

	-- Настройки: ссылки и смайлики
	["Detect links"] = "Распознавать ссылки",
	["Highlight links in messages and make them clickable."] =
		"Подсвечивает ссылки в сообщениях и делает их нажимаемыми.",
	["Link colour"] = "Цвет ссылок",
	["Emoticon style"] = "Вид смайликов",
	["Text"] = "Текст",
	["Coloured text"] = "Цветной текст",
	["Images"] = "Картинки",
	["Convert raid target markers"] = "Заменять рейдовые метки значками",

	-- Настройки: дополнительно
	["Debug messages"] = "Отладочные сообщения",
	["Reset everything"] = "Сбросить всё",
	["Profile"] = "Профиль",
	["Diagnostics"] = "Диагностика",
	["Client"] = "Клиент",
	["Reset window positions"] = "Сбросить положение окон",

	-- Выбор эмодзи
	["Smileys"] = "Смайлики",
	["Symbols"] = "Символы",
	["Markers"] = "Метки",
	["Recent"] = "Недавние",

	-- Уведомления
	["%s is offline. Message not delivered."] =
		"%s не в сети. Сообщение не доставлено.",
	["Message too long, sent as %d parts."] =
		"Сообщение слишком длинное, отправлено %d частями.",

	-- Справка по командам
	["Commands:"] = "Команды:",
	["/wtw - toggle the messenger"] = "/wtw -- открыть или закрыть мессенджер",
	["Right-click for the list"] = "Правый щелчок -- список",
	["Mark all as read"] = "Отметить всё прочитанным",
	["Hide minimap button"] = "Скрыть кнопку у миникарты",
	["/wtw config - open settings"] = "/wtw config -- открыть настройки",
	["/wtw <name> - open a conversation"] = "/wtw <имя> -- открыть разговор",
	["/wtw clear - clear all history"] = "/wtw clear -- очистить всю историю",
	["/wtw diag - print client diagnostics"] =
		"/wtw diag -- вывести диагностику клиента",

	-- Подписи, добавленные вместе со схемой настроек
	["Drop shadows"] = "Тени",
	["Square"] = "Прямые",
	["Round"] = "Скруглённые",
	["Always"] = "Всегда",
	["Timestamp on hover"] = "Время при наведении",
	["Maximum toasts"] = "Макс. уведомлений сразу",
	["Show delivery state"] = "Показывать состояние доставки",
	["Show whether the server accepted each message you send."] =
		"Показывает, принял ли сервер каждое отправленное вами сообщение.",
	["Mark read when focused"] = "Считать прочитанным при переходе в окно",
	["Timestamps"] = "Время",
	["Reset all settings?"] = "Сбросить все настройки?",
	["Every option goes back to its default. Message history is not touched."] =
		"Каждая настройка вернётся к исходному значению. История сообщений не затрагивается.",
	["Reset"] = "Сбросить",
	["Enter a character name"] = "Введите имя персонажа",
	["Name"] = "Имя",
	["Open"] = "Открыть",
	["Whisper a player"] = "Шепнуть игроку",
	["Something went wrong repeatedly, so whispers are being shown in the chat frame again. /wtw debug for details."] =
		"Что-то несколько раз пошло не так, поэтому шёпот снова выводится в окне чата. Подробности -- /wtw debug.",
	["Whispers here cannot be read by addons, so they are being shown in the chat frame instead."] =
		"Здесь аддоны не могут прочитать шёпот, поэтому он показывается в окне чата.",
	["Debug logging on."] = "Отладочный журнал включён.",
	["Debug logging off."] = "Отладочный журнал выключен.",
	["/wtw show / hide - open or close the messenger"] =
		"/wtw show / hide -- открыть или закрыть мессенджер",
	["/wtw debug - toggle developer logging"] =
		"/wtw debug -- включить или выключить журнал разработчика",
	["/wtw reset - restore default settings"] =
		"/wtw reset -- вернуть исходные настройки",
	["WhatTheWhisper is ready. Type /wtw to open it."] =
		"WhatTheWhisper готов. Введите /wtw, чтобы открыть его.",
	["Theme"] = "Тема",
	["Language"] = "Язык",
	["Independent of the game's own language."] = "Не зависит от языка самой игры.",
	["Typography"] = "Шрифты",
	["Show chat bubbles"] = "Показывать облачка сообщений",
	["Delivery"] = "Доставка",
	["Mode"] = "Режим",
	["Nothing logged yet."] = "В журнале пока пусто.",
	["/wtw debug log - show the last few entries"] =
		"/wtw debug log -- показать последние записи",
	["Open when you start a whisper"] = "Открывать, когда вы начинаете шёпот",
	["Typing /w in the default chat box opens that conversation here."] =
		"Набранное /w в обычной строке чата открывает этот разговор здесь.",
})
