-- WhatTheWhisper -- Português (Brasil).
--
-- `true` quer dizer "igual ao inglês", escrito de propósito: o nome de um
-- produto ou de um formato não se traduz, e dizer isso aqui é a diferença entre
-- "nós decidimos" e "alguém esqueceu a linha".

local _, ns = ...

ns.RegisterLocale("ptBR", {
	-- Janela
	["WhatTheWhisper"] = true,
	["Conversations"] = "Conversas",
	["Search conversations"] = "Procurar conversas",
	["Search messages"] = "Procurar mensagens",
	["Character details"] = "Detalhes do personagem",
	["Class, level, guild, zone and realm under the header."] =
		"Classe, nível, guilda, zona e reino abaixo do cabeçalho.",
	["Class"] = "Classe",
	["Race"] = "Raça",
	["Guild"] = "Guilda",
	["Zone"] = "Zona",
	["Realm"] = "Reino",
	["BattleTag"] = true,
	["Character"] = "Personagem",
	["not known"] = "não se sabe",
	["Looking up..."] = "Consultando...",
	["Try again in a moment"] = "Tente de novo daqui a pouco",
	["New conversation"] = "Nova conversa",
	["Settings"] = "Configurações",
	["All windows"] = "Todas as janelas",
	["Show every open conversation window side by side."] =
		"Mostra lado a lado todas as janelas de conversa abertas.",
	["Click a window to go to it, or press Escape"] =
		"Clique em uma janela para ir até ela, ou aperte Esc",
	["Minimize"] = "Minimizar",
	["Close"] = "Fechar",
	["Maximize"] = "Maximizar",
	["Restore"] = "Restaurar",
	["Pop out"] = "Destacar",
	["Dock"] = "Encaixar",
	["Pin"] = "Fixar",
	["Unpin"] = "Desafixar",
	["Back"] = "Voltar",

	-- Redação
	["Message %s..."] = "Mensagem para %s...",
	["Type a message..."] = "Escreva uma mensagem...",
	["Send"] = "Enviar",
	["Emoji"] = "Emoji",
	["%d characters over the limit"] = "%d caracteres a mais",
	["Will be sent as %d messages"] = "Será enviado em %d mensagens",

	-- Estado das conversas
	["Today"] = "Hoje",
	["Yesterday"] = "Ontem",
	["Online"] = "Conectado",
	["Offline"] = "Desconectado",
	["Away"] = "Ausente",
	["Busy"] = "Ocupado",
	["Muted"] = "Silenciada",
	["Pinned"] = "Fixada",
	["You"] = "Você",
	["Delivered"] = "Entregue",
	["Sending"] = "Enviando",
	["Not delivered"] = "Não entregue",
	["%s is not online"] = "%s não está conectado",
	["There is no character named %s."] = "Não existe personagem chamado %s.",
	["Character names are 2 to 12 letters, with no spaces, numbers or punctuation."] =
		"Nomes de personagem têm de 2 a 12 letras, sem espaços, números ou pontuação.",
	["That realm name is not valid."] = "Esse nome de reino não é válido.",
	["A BattleTag looks like Name#1234."] = "Uma BattleTag é do tipo Nome#1234.",
	["%d new messages"] = "%d mensagens novas",
	["1 new message"] = "1 mensagem nova",
	["Level %d"] = "Nível %d",
	["Battle.net"] = true,

	-- Estados vazios
	["No conversations yet"] = "Ainda não há conversas",
	["Whisper someone to start a conversation."] =
		"Sussurre para alguém para começar uma conversa.",
	["Pick a conversation"] = "Escolha uma conversa",
	["Your whispers are kept here, one thread per player."] =
		"Seus sussurros ficam aqui, uma conversa por jogador.",
	["No matches"] = "Nenhum resultado",
	["Try a different name or word."] = "Tente outro nome ou outra palavra.",
	["Start the conversation"] = "Comece a conversa",
	["Say hi to %s."] = "Diga oi para %s.",
	["History is off"] = "O histórico está desligado",
	["Enable it in Settings > History to keep messages."] =
		"Ligue em Configurações > Histórico para guardar as mensagens.",
	["Nothing to show"] = "Nada para mostrar",

	-- Menu de contexto
	["Whisper"] = "Sussurrar",
	["Invite to group"] = "Convidar para o grupo",
	["Add friend"] = "Adicionar aos amigos",
	["Ignore"] = "Ignorar",
	["Copy name"] = "Copiar o nome",
	["Copy message"] = "Copiar a mensagem",
	["Copy conversation"] = "Copiar a conversa",
	["Export conversation"] = "Exportar a conversa",
	["Clear history"] = "Apagar o histórico",
	["Mute conversation"] = "Silenciar a conversa",
	["Unmute conversation"] = "Reativar o som da conversa",
	["Pin conversation"] = "Fixar a conversa",
	["Unpin conversation"] = "Desafixar a conversa",
	["Close conversation"] = "Fechar a conversa",
	["Target"] = "Selecionar",
	["Look up"] = "Consultar",
	["Mark as read"] = "Marcar como lida",
	["Mark as unread"] = "Marcar como não lida",
	["Copy URL"] = "Copiar a URL",
	["Open in copy box"] = "Abrir na caixa de cópia",

	-- Caixas de diálogo
	["Copy"] = "Copiar",
	["Press Ctrl+C to copy, then Esc to close."] =
		"Aperte Ctrl+C para copiar e Esc para fechar.",
	["Press Ctrl+C to copy, or save it to a file."] =
		"Aperte Ctrl+C para copiar, ou salve em um arquivo.",
	["Save to file"] = "Salvar em arquivo",
	["Saved. It is in %s after your next reload or logout."] =
		"Salvo. Fica em %s depois do próximo reload ou logout.",
	["That conversation is too large to save."] =
		"Essa conversa é grande demais para salvar.",
	["There was nothing to save."] = "Não havia nada para salvar.",
	["Export"] = "Exportar",
	["Format"] = "Formato",
	["Plain text"] = "Texto simples",
	["BBCode"] = true,
	["Markdown"] = true,
	["CSV"] = true,
	["Clear this conversation?"] = "Apagar esta conversa?",
	["Clear all history?"] = "Apagar todo o histórico?",
	["This removes %d stored messages. It cannot be undone."] =
		"Isso remove %d mensagens guardadas. Não dá para desfazer.",
	["This removes every stored message in %d conversations. It cannot be undone."] =
		"Isso remove todas as mensagens guardadas em %d conversas. Não dá para desfazer.",
	["Cancel"] = "Cancelar",
	["Confirm"] = "Confirmar",
	["Delete"] = "Excluir",

	-- Categorias das configurações
	["General"] = "Geral",
	["Appearance"] = "Aparência",
	["Messages"] = "Mensagens",
	["History"] = "Histórico",
	["Sounds"] = "Sons",
	["Notifications"] = "Notificações",
	["Animations"] = "Animações",
	["Tabs"] = "Abas",
	["Windows"] = "Janelas",
	["Combat"] = "Combate",
	["Links"] = "Links",
	["Emoticons"] = "Emoticons",
	["Advanced"] = "Avançado",
	["Search settings"] = "Procurar nas configurações",
	["No settings match your search"] = "Nenhuma configuração corresponde à busca",
	["Try a shorter word, or clear the search."] =
		"Tente uma palavra mais curta, ou limpe a busca.",
	["Nothing here yet"] = "Ainda não há nada aqui",

	-- Configurações: geral
	["Enable WhatTheWhisper"] = "Ativar o WhatTheWhisper",
	["Route whispers into the messenger instead of the default chat frame."] =
		"Leva os sussurros para o mensageiro em vez da janela de chat comum.",
	["Hide whispers from chat frames"] = "Ocultar os sussurros nas janelas de chat",
	["Whispers still arrive normally, they are just not printed in the chat window."] =
		"Os sussurros continuam chegando normalmente, só não aparecem escritos na janela de chat.",
	["Open on new whisper"] = "Abrir a cada sussurro novo",
	["Show the messenger automatically when someone whispers you."] =
		"Mostra o mensageiro sozinho quando alguém sussurra para você.",
	["Auto-switch to new conversations"] = "Mudar sozinho para as conversas novas",
	["Switching away from what you are reading is off by default."] =
		"Sair do que você está lendo vem desligado de fábrica.",
	["Minimap button"] = "Botão no minimapa",
	["Show a button on the minimap to toggle the messenger."] =
		"Mostra um botão no minimapa para abrir e fechar o mensageiro.",
	["Keep messenger open in combat"] = "Manter o mensageiro aberto em combate",

	-- Configurações: aparência
	["Skin"] = "Estilo",
	["Font"] = "Fonte",
	["Font size"] = "Tamanho da fonte",
	["Background opacity"] = "Opacidade do fundo",
	["Corner radius"] = "Raio dos cantos",
	["Density"] = "Densidade",
	["Comfortable"] = "Folgada",
	["Compact"] = "Compacta",
	["Sidebar width"] = "Largura da barra lateral",
	["Use class colours"] = "Usar as cores das classes",
	["Show timestamps"] = "Mostrar o horário",
	["Timestamp format"] = "Formato do horário",
	["24 hour"] = "24 horas",
	["12 hour"] = "12 horas",
	["Show avatars"] = "Mostrar avatares",
	["Avatar style"] = "Estilo do avatar",
	["Automatic"] = "Automático",
	["Class icon"] = "Ícone da classe",
	["Initials"] = "Iniciais",
	["Chat bubbles"] = "Balões de fala",
	["Group messages"] = "Agrupar mensagens",
	["Collapse consecutive messages from the same player."] =
		"Junta as mensagens seguidas do mesmo jogador.",
	["Show date separators"] = "Mostrar separadores de data",
	["Bubble opacity"] = "Opacidade dos balões",
	["Message spacing"] = "Espaço entre as mensagens",

	-- Configurações: disposição
	["Layout"] = "Disposição",
	["Sidebar"] = "Barra lateral",
	["Tabbed"] = "Em abas",
	["Hybrid"] = "Híbrida",
	["Close tabs after"] = "Fechar as abas depois de",
	["Never"] = "Nunca",
	["%d minutes"] = "%d minutos",
	["Blink unread tabs"] = "Piscar as abas não lidas",
	["Open a tab for every conversation"] = "Abrir uma aba para cada conversa",
	["Snap windows together"] = "Encaixar as janelas entre si",
	["Lock window position"] = "Travar a posição da janela",
	["Remember window positions"] = "Lembrar a posição das janelas",

	-- Configurações: histórico
	["Keep history"] = "Guardar o histórico",
	["Disabled"] = "Desligado",
	["This session"] = "Esta sessão",
	["1 day"] = "1 dia",
	["7 days"] = "7 dias",
	["30 days"] = "30 dias",
	["Unlimited"] = "Sem limite",
	["Max messages per conversation"] = "Máx. de mensagens por conversa",
	["Max conversations"] = "Máx. de conversas",
	["Stored messages: %d in %d conversations"] =
		"Mensagens guardadas: %d em %d conversas",
	["Estimated size: %s"] = "Tamanho estimado: %s",
	["Clear all history"] = "Apagar todo o histórico",

	-- Configurações: sons
	["Sound on new message"] = "Som a cada mensagem nova",
	["Sound when window is hidden"] = "Som com a janela escondida",
	["Sound on mention"] = "Som quando citarem você",
	["Sound when opening a conversation"] = "Som ao abrir uma conversa",
	["Repeat sound cooldown"] = "Espera entre sons repetidos",
	["%d seconds"] = "%d segundos",
	["Do not disturb"] = "Não perturbe",
	["Silence everything until you turn this off."] =
		"Silencia tudo até você desligar isto.",
	["Mute in combat"] = "Silenciar em combate",
	["Mute in dungeons"] = "Silenciar em masmorras",
	["Mute in raids"] = "Silenciar em raides",
	["Mute in arenas"] = "Silenciar em arenas",
	["Mute in battlegrounds"] = "Silenciar em campos de batalha",
	["None"] = "Nenhum",
	["Custom file"] = "Arquivo próprio",
	["Sound file path"] = "Caminho do arquivo de som",

	-- Configurações: notificações
	["Show toast notifications"] = "Mostrar avisos flutuantes",
	["Toast position"] = "Posição dos avisos",
	["Top right"] = "Canto superior direito",
	["Top left"] = "Canto superior esquerdo",
	["Bottom right"] = "Canto inferior direito",
	["Bottom left"] = "Canto inferior esquerdo",
	["Toast duration"] = "Duração dos avisos",
	["Flash taskbar icon"] = "Piscar o ícone na barra de tarefas",
	["Show unread badge"] = "Mostrar o contador de não lidas",
	["Summarise repeated messages"] = "Resumir as mensagens repetidas",

	-- Configurações: animações
	["Animation level"] = "Nível de animação",
	["Off"] = "Desligadas",
	["Reduced"] = "Reduzidas",
	["Normal"] = "Normais",
	["Fancy"] = "Caprichadas",
	["Smooth scrolling"] = "Rolagem suave",

	-- Configurações: combate
	["Entering combat"] = "Ao entrar em combate",
	["Do nothing"] = "Não fazer nada",
	["Fade conversations"] = "Esmaecer as conversas",
	["Minimize conversations"] = "Minimizar as conversas",
	["Hide conversations"] = "Ocultar as conversas",
	["Leaving combat"] = "Ao sair do combate",
	["Restore previous state"] = "Voltar ao estado anterior",
	["Stay hidden"] = "Continuar oculto",
	["Combat fade opacity"] = "Opacidade ao esmaecer em combate",

	-- Configurações: links e emoticons
	["Detect links"] = "Detectar links",
	["Highlight links in messages and make them clickable."] =
		"Destaca os links nas mensagens e deixa clicar neles.",
	["Link colour"] = "Cor dos links",
	["Emoticon style"] = "Estilo dos emoticons",
	["Text"] = "Texto",
	["Coloured text"] = "Texto colorido",
	["Images"] = "Imagens",
	["Convert raid target markers"] = "Converter as marcas de alvo",

	-- Configurações: avançado
	["Debug messages"] = "Mensagens de depuração",
	["Reset everything"] = "Redefinir tudo",
	["Profile"] = "Perfil",
	["Diagnostics"] = "Diagnóstico",
	["Client"] = "Cliente",
	["Reset window positions"] = "Redefinir a posição das janelas",

	-- Seletor de emoji
	["Smileys"] = "Carinhas",
	["Symbols"] = "Símbolos",
	["Markers"] = "Marcas",
	["Recent"] = "Recentes",

	-- Avisos
	["%s is offline. Message not delivered."] =
		"%s está desconectado. A mensagem não foi entregue.",
	["Message too long, sent as %d parts."] =
		"Mensagem longa demais, enviada em %d partes.",

	-- Ajuda dos comandos
	["Commands:"] = "Comandos:",
	["/wtw - toggle the messenger"] = "/wtw - abre ou fecha o mensageiro",
	["Right-click for the list"] = "Clique direito para ver a lista",
	["Mark all as read"] = "Marcar tudo como lido",
	["Hide minimap button"] = "Ocultar o botão do minimapa",
	["/wtw config - open settings"] = "/wtw config - abre as configurações",
	["/wtw <name> - open a conversation"] = "/wtw <nome> - abre uma conversa",
	["/wtw clear - clear all history"] = "/wtw clear - apaga todo o histórico",
	["/wtw diag - print client diagnostics"] =
		"/wtw diag - mostra o diagnóstico do cliente",

	-- Rótulos adicionados com o esquema das configurações
	["Drop shadows"] = "Sombras",
	["Square"] = "Retos",
	["Round"] = "Arredondados",
	["Always"] = "Sempre",
	["Timestamp on hover"] = "Horário ao passar o mouse",
	["Maximum toasts"] = "Máx. de avisos ao mesmo tempo",
	["Show delivery state"] = "Mostrar o estado da entrega",
	["Show whether the server accepted each message you send."] =
		"Mostra se o servidor aceitou cada mensagem que você envia.",
	["Mark read when focused"] = "Marcar como lida ao trazer para a frente",
	["Timestamps"] = "Horário",
	["Reset all settings?"] = "Redefinir todas as configurações?",
	["Every option goes back to its default. Message history is not touched."] =
		"Cada opção volta ao valor de fábrica. O histórico de mensagens não é tocado.",
	["Reset"] = "Redefinir",
	["Enter a character name"] = "Escreva o nome de um personagem",
	["Name"] = "Nome",
	["Open"] = "Abrir",
	["Whisper a player"] = "Sussurrar para um jogador",
	["Something went wrong repeatedly, so whispers are being shown in the chat frame again. /wtw debug for details."] =
		"Algo deu errado várias vezes, então os sussurros voltaram para a janela de chat. /wtw debug para os detalhes.",
	["Whispers here cannot be read by addons, so they are being shown in the chat frame instead."] =
		"Aqui os addons não conseguem ler os sussurros, então eles aparecem na janela de chat.",
	["Debug logging on."] = "Registro de depuração ligado.",
	["Debug logging off."] = "Registro de depuração desligado.",
	["/wtw show / hide - open or close the messenger"] =
		"/wtw show / hide - abre ou fecha o mensageiro",
	["/wtw debug - toggle developer logging"] =
		"/wtw debug - liga ou desliga o registro de desenvolvimento",
	["/wtw reset - restore default settings"] =
		"/wtw reset - restaura as configurações de fábrica",
	["WhatTheWhisper is ready. Type /wtw to open it."] =
		"O WhatTheWhisper está pronto. Escreva /wtw para abrir.",
	["Theme"] = "Tema",
	["Language"] = "Idioma",
	["Independent of the game's own language."] = "Independente do idioma do jogo.",
	["Typography"] = "Tipografia",
	["Show chat bubbles"] = "Mostrar balões de fala",
	["Delivery"] = "Entrega",
	["Mode"] = "Modo",
	["Nothing logged yet."] = "Ainda não há nada no registro.",
	["/wtw debug log - show the last few entries"] =
		"/wtw debug log - mostra as últimas entradas",
	["Open when you start a whisper"] = "Abrir quando você começar um sussurro",
	["Typing /w in the default chat box opens that conversation here."] =
		"Escrever /w no chat comum abre aqui aquela conversa.",
})
