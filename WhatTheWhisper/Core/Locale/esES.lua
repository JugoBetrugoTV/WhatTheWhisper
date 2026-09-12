-- WhatTheWhisper -- Español (Europa).
--
-- `true` significa "igual que en inglés", escrito a propósito: el nombre de un
-- producto o de un formato no se traduce, y decirlo aquí es la diferencia entre
-- "lo hemos decidido" y "a alguien se le olvidó la línea".

local _, ns = ...

ns.RegisterLocale("esES", {
	-- Ventana
	["WhatTheWhisper"] = true,
	["Conversations"] = "Conversaciones",
	["Search conversations"] = "Buscar conversaciones",
	["Search messages"] = "Buscar mensajes",
	["Character details"] = "Detalles del personaje",
	["Class, level, guild, zone and realm under the header."] =
		"Clase, nivel, hermandad, zona y reino bajo la cabecera.",
	["Class"] = "Clase",
	["Race"] = "Raza",
	["Guild"] = "Hermandad",
	["Zone"] = "Zona",
	["Realm"] = "Reino",
	["BattleTag"] = true,
	["Character"] = "Personaje",
	["not known"] = "se desconoce",
	["Looking up..."] = "Buscando...",
	["Try again in a moment"] = "Inténtalo de nuevo en un momento",
	["New conversation"] = "Nueva conversación",
	["Settings"] = "Ajustes",
	["All windows"] = "Todas las ventanas",
	["Show every open conversation window side by side."] =
		"Muestra una junto a otra todas las ventanas de conversación abiertas.",
	["Click a window to go to it, or press Escape"] =
		"Haz clic en una ventana para ir a ella, o pulsa Escape",
	["Minimize"] = "Minimizar",
	["Close"] = "Cerrar",
	["Maximize"] = "Maximizar",
	["Restore"] = "Restaurar",
	["Pop out"] = "Separar",
	["Dock"] = "Acoplar",
	["Pin"] = "Fijar",
	["Unpin"] = "Soltar",
	["Back"] = "Atrás",

	-- Redacción
	["Message %s..."] = "Mensaje para %s...",
	["Type a message..."] = "Escribe un mensaje...",
	["Send"] = "Enviar",
	["Emoji"] = "Emoji",
	["%d characters over the limit"] = "%d caracteres de más",
	["Will be sent as %d messages"] = "Se enviará en %d mensajes",

	-- Estado de las conversaciones
	["Today"] = "Hoy",
	["Yesterday"] = "Ayer",
	["Online"] = "Conectado",
	["Offline"] = "Desconectado",
	["Away"] = "Ausente",
	["Busy"] = "Ocupado",
	["Muted"] = "Silenciada",
	["Pinned"] = "Fijada",
	["You"] = "Tú",
	["Delivered"] = "Entregado",
	["Sending"] = "Enviando",
	["Not delivered"] = "No entregado",
	["%s is not online"] = "%s no está conectado",
	["There is no character named %s."] = "No existe ningún personaje llamado %s.",
	["Character names are 2 to 12 letters, with no spaces, numbers or punctuation."] =
		"Los nombres de personaje tienen de 2 a 12 letras, sin espacios, números ni signos.",
	["That realm name is not valid."] = "Ese nombre de reino no es válido.",
	["A BattleTag looks like Name#1234."] = "Un BattleTag es del tipo Nombre#1234.",
	["%d new messages"] = "%d mensajes nuevos",
	["1 new message"] = "1 mensaje nuevo",
	["Level %d"] = "Nivel %d",
	["Battle.net"] = true,

	-- Estados vacíos
	["No conversations yet"] = "Aún no hay conversaciones",
	["Whisper someone to start a conversation."] =
		"Susurra a alguien para empezar una conversación.",
	["Pick a conversation"] = "Elige una conversación",
	["Your whispers are kept here, one thread per player."] =
		"Tus susurros se guardan aquí, un hilo por jugador.",
	["No matches"] = "Sin resultados",
	["Try a different name or word."] = "Prueba con otro nombre u otra palabra.",
	["Start the conversation"] = "Empieza la conversación",
	["Say hi to %s."] = "Saluda a %s.",
	["History is off"] = "El historial está desactivado",
	["Enable it in Settings > History to keep messages."] =
		"Actívalo en Ajustes > Historial para conservar los mensajes.",
	["Nothing to show"] = "No hay nada que mostrar",

	-- Menú contextual
	["Whisper"] = "Susurrar",
	["Invite to group"] = "Invitar al grupo",
	["Add friend"] = "Añadir a amigos",
	["Ignore"] = "Ignorar",
	["Copy name"] = "Copiar nombre",
	["Copy message"] = "Copiar mensaje",
	["Copy conversation"] = "Copiar conversación",
	["Export conversation"] = "Exportar conversación",
	["Clear history"] = "Borrar historial",
	["Mute conversation"] = "Silenciar conversación",
	["Unmute conversation"] = "Dejar de silenciar",
	["Pin conversation"] = "Fijar conversación",
	["Unpin conversation"] = "Soltar conversación",
	["Close conversation"] = "Cerrar conversación",
	["Target"] = "Seleccionar",
	["Look up"] = "Consultar",
	["Mark as read"] = "Marcar como leída",
	["Mark as unread"] = "Marcar como no leída",
	["Copy URL"] = "Copiar URL",
	["Open in copy box"] = "Abrir en el cuadro de copia",

	-- Diálogos
	["Copy"] = "Copiar",
	["Press Ctrl+C to copy, then Esc to close."] =
		"Pulsa Ctrl+C para copiar y Esc para cerrar.",
	["Press Ctrl+C to copy, or save it to a file."] =
		"Pulsa Ctrl+C para copiar, o guárdalo en un archivo.",
	["Save to file"] = "Guardar en archivo",
	["Saved. It is in %s after your next reload or logout."] =
		"Guardado. Estará en %s tras recargar o salir.",
	["That conversation is too large to save."] =
		"Esa conversación es demasiado grande para guardarla.",
	["There was nothing to save."] = "No había nada que guardar.",
	["Export"] = "Exportar",
	["Format"] = "Formato",
	["Plain text"] = "Texto sin formato",
	["BBCode"] = true,
	["Markdown"] = true,
	["CSV"] = true,
	["Clear this conversation?"] = "¿Borrar esta conversación?",
	["Clear all history?"] = "¿Borrar todo el historial?",
	["This removes %d stored messages. It cannot be undone."] =
		"Esto elimina %d mensajes guardados. No se puede deshacer.",
	["This removes every stored message in %d conversations. It cannot be undone."] =
		"Esto elimina todos los mensajes guardados de %d conversaciones. No se puede deshacer.",
	["Cancel"] = "Cancelar",
	["Confirm"] = "Confirmar",
	["Delete"] = "Eliminar",

	-- Categorías de ajustes
	["General"] = "General",
	["Appearance"] = "Apariencia",
	["Messages"] = "Mensajes",
	["History"] = "Historial",
	["Sounds"] = "Sonidos",
	["Notifications"] = "Notificaciones",
	["Animations"] = "Animaciones",
	["Tabs"] = "Pestañas",
	["Windows"] = "Ventanas",
	["Combat"] = "Combate",
	["Links"] = "Enlaces",
	["Emoticons"] = "Emoticonos",
	["Advanced"] = "Avanzado",
	["Search settings"] = "Buscar ajustes",
	["No settings match your search"] = "Ningún ajuste coincide con tu búsqueda",
	["Try a shorter word, or clear the search."] =
		"Prueba con una palabra más corta, o borra la búsqueda.",
	["Nothing here yet"] = "Aquí todavía no hay nada",

	-- Ajustes: general
	["Enable WhatTheWhisper"] = "Activar WhatTheWhisper",
	["Route whispers into the messenger instead of the default chat frame."] =
		"Lleva los susurros al mensajero en lugar de a la ventana de chat normal.",
	["Hide whispers from chat frames"] = "Ocultar los susurros en las ventanas de chat",
	["Whispers still arrive normally, they are just not printed in the chat window."] =
		"Los susurros siguen llegando igual, solo que no se escriben en la ventana de chat.",
	["Open on new whisper"] = "Abrir con cada susurro nuevo",
	["Show the messenger automatically when someone whispers you."] =
		"Muestra el mensajero automáticamente cuando alguien te susurra.",
	["Auto-switch to new conversations"] = "Cambiar solo a las conversaciones nuevas",
	["Switching away from what you are reading is off by default."] =
		"Apartarte de lo que estás leyendo está desactivado de serie.",
	["Minimap button"] = "Botón del minimapa",
	["Show a button on the minimap to toggle the messenger."] =
		"Muestra un botón en el minimapa para abrir y cerrar el mensajero.",
	["Keep messenger open in combat"] = "Mantener el mensajero abierto en combate",

	-- Ajustes: apariencia
	["Skin"] = "Aspecto",
	["Font"] = "Fuente",
	["Font size"] = "Tamaño de fuente",
	["Background opacity"] = "Opacidad del fondo",
	["Corner radius"] = "Radio de las esquinas",
	["Density"] = "Densidad",
	["Comfortable"] = "Holgada",
	["Compact"] = "Compacta",
	["Sidebar width"] = "Ancho de la barra lateral",
	["Use class colours"] = "Usar colores de clase",
	["Show timestamps"] = "Mostrar la hora",
	["Timestamp format"] = "Formato de la hora",
	["24 hour"] = "24 horas",
	["12 hour"] = "12 horas",
	["Show avatars"] = "Mostrar avatares",
	["Avatar style"] = "Estilo de avatar",
	["Automatic"] = "Automático",
	["Class icon"] = "Icono de clase",
	["Initials"] = "Iniciales",
	["Chat bubbles"] = "Burbujas de chat",
	["Group messages"] = "Agrupar mensajes",
	["Collapse consecutive messages from the same player."] =
		"Agrupa los mensajes seguidos del mismo jugador.",
	["Show date separators"] = "Mostrar separadores de fecha",
	["Bubble opacity"] = "Opacidad de las burbujas",
	["Message spacing"] = "Espaciado entre mensajes",

	-- Ajustes: disposición
	["Layout"] = "Disposición",
	["Sidebar"] = "Barra lateral",
	["Tabbed"] = "Pestañas",
	["Hybrid"] = "Híbrida",
	["Close tabs after"] = "Cerrar pestañas tras",
	["Never"] = "Nunca",
	["%d minutes"] = "%d minutos",
	["Blink unread tabs"] = "Parpadeo en pestañas sin leer",
	["Open a tab for every conversation"] = "Abrir una pestaña por conversación",
	["Snap windows together"] = "Alinear las ventanas entre sí",
	["Lock window position"] = "Bloquear la posición de la ventana",
	["Remember window positions"] = "Recordar la posición de las ventanas",

	-- Ajustes: historial
	["Keep history"] = "Guardar historial",
	["Disabled"] = "Desactivado",
	["This session"] = "Esta sesión",
	["1 day"] = "1 día",
	["7 days"] = "7 días",
	["30 days"] = "30 días",
	["Unlimited"] = "Sin límite",
	["Max messages per conversation"] = "Máx. mensajes por conversación",
	["Max conversations"] = "Máx. conversaciones",
	["Stored messages: %d in %d conversations"] =
		"Mensajes guardados: %d en %d conversaciones",
	["Estimated size: %s"] = "Tamaño estimado: %s",
	["Clear all history"] = "Borrar todo el historial",

	-- Ajustes: sonidos
	["Sound on new message"] = "Sonido al recibir un mensaje",
	["Sound when window is hidden"] = "Sonido con la ventana oculta",
	["Sound on mention"] = "Sonido al mencionarte",
	["Sound when opening a conversation"] = "Sonido al abrir una conversación",
	["Repeat sound cooldown"] = "Espera entre sonidos repetidos",
	["%d seconds"] = "%d segundos",
	["Do not disturb"] = "No molestar",
	["Silence everything until you turn this off."] =
		"Silencia todo hasta que lo desactives.",
	["Mute in combat"] = "Silenciar en combate",
	["Mute in dungeons"] = "Silenciar en mazmorras",
	["Mute in raids"] = "Silenciar en bandas",
	["Mute in arenas"] = "Silenciar en arenas",
	["Mute in battlegrounds"] = "Silenciar en campos de batalla",
	["None"] = "Ninguno",
	["Custom file"] = "Archivo propio",
	["Sound file path"] = "Ruta del archivo de sonido",

	-- Ajustes: notificaciones
	["Show toast notifications"] = "Mostrar avisos emergentes",
	["Toast position"] = "Posición de los avisos",
	["Top right"] = "Arriba a la derecha",
	["Top left"] = "Arriba a la izquierda",
	["Bottom right"] = "Abajo a la derecha",
	["Bottom left"] = "Abajo a la izquierda",
	["Toast duration"] = "Duración de los avisos",
	["Flash taskbar icon"] = "Parpadear el icono de la barra de tareas",
	["Show unread badge"] = "Mostrar el contador de no leídos",
	["Summarise repeated messages"] = "Resumir los mensajes repetidos",

	-- Ajustes: animaciones
	["Animation level"] = "Nivel de animación",
	["Off"] = "Desactivadas",
	["Reduced"] = "Reducidas",
	["Normal"] = "Normales",
	["Fancy"] = "Elaboradas",
	["Smooth scrolling"] = "Desplazamiento suave",

	-- Ajustes: combate
	["Entering combat"] = "Al entrar en combate",
	["Do nothing"] = "No hacer nada",
	["Fade conversations"] = "Atenuar las conversaciones",
	["Minimize conversations"] = "Minimizar las conversaciones",
	["Hide conversations"] = "Ocultar las conversaciones",
	["Leaving combat"] = "Al salir de combate",
	["Restore previous state"] = "Restaurar el estado anterior",
	["Stay hidden"] = "Seguir ocultas",
	["Combat fade opacity"] = "Opacidad al atenuar en combate",

	-- Ajustes: enlaces y emoticonos
	["Detect links"] = "Detectar enlaces",
	["Highlight links in messages and make them clickable."] =
		"Resalta los enlaces de los mensajes y permite hacer clic en ellos.",
	["Link colour"] = "Color de los enlaces",
	["Emoticon style"] = "Estilo de los emoticonos",
	["Text"] = "Texto",
	["Coloured text"] = "Texto de color",
	["Images"] = "Imágenes",
	["Convert raid target markers"] = "Convertir las marcas de objetivo de banda",

	-- Ajustes: avanzado
	["Debug messages"] = "Mensajes de depuración",
	["Reset everything"] = "Restablecer todo",
	["Profile"] = "Perfil",
	["Diagnostics"] = "Diagnóstico",
	["Client"] = "Cliente",
	["Reset window positions"] = "Restablecer la posición de las ventanas",

	-- Selector de emoji
	["Smileys"] = "Caras",
	["Symbols"] = "Símbolos",
	["Markers"] = "Marcas",
	["Recent"] = "Recientes",

	-- Avisos
	["%s is offline. Message not delivered."] =
		"%s está desconectado. El mensaje no se ha entregado.",
	["Message too long, sent as %d parts."] =
		"Mensaje demasiado largo, enviado en %d partes.",

	-- Ayuda de los comandos
	["Commands:"] = "Comandos:",
	["/wtw - toggle the messenger"] = "/wtw - abre o cierra el mensajero",
	["Right-click for the list"] = "Clic derecho para ver la lista",
	["Mark all as read"] = "Marcar todo como leído",
	["Hide minimap button"] = "Ocultar el botón del minimapa",
	["/wtw config - open settings"] = "/wtw config - abre los ajustes",
	["/wtw <name> - open a conversation"] = "/wtw <nombre> - abre una conversación",
	["/wtw clear - clear all history"] = "/wtw clear - borra todo el historial",
	["/wtw diag - print client diagnostics"] =
		"/wtw diag - muestra el diagnóstico del cliente",

	-- Etiquetas añadidas con el esquema de ajustes
	["Drop shadows"] = "Sombras",
	["Square"] = "Cuadradas",
	["Round"] = "Redondeadas",
	["Always"] = "Siempre",
	["Timestamp on hover"] = "Hora al pasar el ratón",
	["Maximum toasts"] = "Máx. avisos a la vez",
	["Show delivery state"] = "Mostrar el estado de entrega",
	["Show whether the server accepted each message you send."] =
		"Muestra si el servidor ha aceptado cada mensaje que envías.",
	["Mark read when focused"] = "Marcar como leída al ponerla en primer plano",
	["Timestamps"] = "Hora",
	["Reset all settings?"] = "¿Restablecer todos los ajustes?",
	["Every option goes back to its default. Message history is not touched."] =
		"Cada opción vuelve a su valor inicial. El historial de mensajes no se toca.",
	["Reset"] = "Restablecer",
	["Enter a character name"] = "Escribe el nombre de un personaje",
	["Name"] = "Nombre",
	["Open"] = "Abrir",
	["Whisper a player"] = "Susurrar a un jugador",
	["Something went wrong repeatedly, so whispers are being shown in the chat frame again. /wtw debug for details."] =
		"Algo ha fallado varias veces, así que los susurros vuelven a mostrarse en la ventana de chat. /wtw debug para más detalles.",
	["Whispers here cannot be read by addons, so they are being shown in the chat frame instead."] =
		"Aquí los complementos no pueden leer los susurros, así que se muestran en la ventana de chat.",
	["Debug logging on."] = "Registro de depuración activado.",
	["Debug logging off."] = "Registro de depuración desactivado.",
	["/wtw show / hide - open or close the messenger"] =
		"/wtw show / hide - abre o cierra el mensajero",
	["/wtw debug - toggle developer logging"] =
		"/wtw debug - activa o desactiva el registro de desarrollo",
	["/wtw reset - restore default settings"] =
		"/wtw reset - restaura los ajustes iniciales",
	["WhatTheWhisper is ready. Type /wtw to open it."] =
		"WhatTheWhisper está listo. Escribe /wtw para abrirlo.",
	["Theme"] = "Tema",
	["Language"] = "Idioma",
	["Independent of the game's own language."] = "Independiente del idioma del juego.",
	["Typography"] = "Tipografía",
	["Show chat bubbles"] = "Mostrar burbujas de chat",
	["Delivery"] = "Entrega",
	["Mode"] = "Modo",
	["Nothing logged yet."] = "Todavía no hay nada registrado.",
	["/wtw debug log - show the last few entries"] =
		"/wtw debug log - muestra las últimas entradas",
	["Open when you start a whisper"] = "Abrir al empezar un susurro",
	["Typing /w in the default chat box opens that conversation here."] =
		"Escribir /w en el chat normal abre aquí esa conversación.",
})
