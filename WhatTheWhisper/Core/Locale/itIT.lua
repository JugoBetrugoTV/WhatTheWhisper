-- WhatTheWhisper -- Italiano.
--
-- `true` significa "uguale all'inglese", scritto di proposito: il nome di un
-- prodotto o di un formato non si traduce, e dirlo qui è la differenza fra
-- "l'abbiamo deciso" e "qualcuno ha dimenticato la riga".

local _, ns = ...

ns.RegisterLocale("itIT", {
	-- Finestra
	["WhatTheWhisper"] = true,
	["Conversations"] = "Conversazioni",
	["Search conversations"] = "Cerca conversazioni",
	["Search messages"] = "Cerca messaggi",
	["Character details"] = "Dettagli del personaggio",
	["Class, level, guild, zone and realm under the header."] =
		"Classe, livello, gilda, zona e reame sotto l'intestazione.",
	["Class"] = "Classe",
	["Race"] = "Razza",
	["Guild"] = "Gilda",
	["Zone"] = "Zona",
	["Realm"] = "Reame",
	["BattleTag"] = true,
	["Character"] = "Personaggio",
	["not known"] = "non si sa",
	["Looking up..."] = "Ricerca in corso...",
	["Try again in a moment"] = "Riprova tra un momento",
	["New conversation"] = "Nuova conversazione",
	["Settings"] = "Impostazioni",
	["All windows"] = "Tutte le finestre",
	["Show every open conversation window side by side."] =
		"Mostra affiancate tutte le finestre di conversazione aperte.",
	["Click a window to go to it, or press Escape"] =
		"Clicca una finestra per andarci, oppure premi Esc",
	["Minimize"] = "Riduci a icona",
	["Close"] = "Chiudi",
	["Maximize"] = "Ingrandisci",
	["Restore"] = "Ripristina",
	["Pop out"] = "Stacca",
	["Dock"] = "Aggancia",
	["Pin"] = "Fissa",
	["Unpin"] = "Libera",
	["Back"] = "Indietro",

	-- Composizione
	["Message %s..."] = "Messaggio per %s...",
	["Type a message..."] = "Scrivi un messaggio...",
	["Send"] = "Invia",
	["Emoji"] = "Emoji",
	["%d characters over the limit"] = "%d caratteri di troppo",
	["Will be sent as %d messages"] = "Verrà inviato in %d messaggi",

	-- Stato delle conversazioni
	["Today"] = "Oggi",
	["Yesterday"] = "Ieri",
	["Online"] = "Online",
	["Offline"] = "Offline",
	["Away"] = "Assente",
	["Busy"] = "Occupato",
	["Muted"] = "Silenziata",
	["Pinned"] = "Fissata",
	["You"] = "Tu",
	["Delivered"] = "Consegnato",
	["Sending"] = "Invio in corso",
	["Not delivered"] = "Non consegnato",
	["%s is not online"] = "%s non è online",
	["There is no character named %s."] = "Non esiste nessun personaggio di nome %s.",
	["Character names are 2 to 12 letters, with no spaces, numbers or punctuation."] =
		"I nomi dei personaggi hanno da 2 a 12 lettere, senza spazi, numeri o punteggiatura.",
	["That realm name is not valid."] = "Quel nome di reame non è valido.",
	["A BattleTag looks like Name#1234."] = "Un BattleTag è del tipo Nome#1234.",
	["%d new messages"] = "%d nuovi messaggi",
	["1 new message"] = "1 nuovo messaggio",
	["Level %d"] = "Livello %d",
	["Battle.net"] = true,

	-- Stati vuoti
	["No conversations yet"] = "Ancora nessuna conversazione",
	["Whisper someone to start a conversation."] =
		"Sussurra a qualcuno per iniziare una conversazione.",
	["Pick a conversation"] = "Scegli una conversazione",
	["Your whispers are kept here, one thread per player."] =
		"I tuoi sussurri restano qui, una conversazione per giocatore.",
	["No matches"] = "Nessun risultato",
	["Try a different name or word."] = "Prova un altro nome o un'altra parola.",
	["Start the conversation"] = "Inizia la conversazione",
	["Say hi to %s."] = "Saluta %s.",
	["History is off"] = "La cronologia è disattivata",
	["Enable it in Settings > History to keep messages."] =
		"Attivala in Impostazioni > Cronologia per conservare i messaggi.",
	["Nothing to show"] = "Niente da mostrare",

	-- Menu contestuale
	["Whisper"] = "Sussurra",
	["Invite to group"] = "Invita nel gruppo",
	["Add friend"] = "Aggiungi agli amici",
	["Ignore"] = "Ignora",
	["Copy name"] = "Copia il nome",
	["Copy message"] = "Copia il messaggio",
	["Copy conversation"] = "Copia la conversazione",
	["Export conversation"] = "Esporta la conversazione",
	["Clear history"] = "Cancella la cronologia",
	["Mute conversation"] = "Silenzia la conversazione",
	["Unmute conversation"] = "Riattiva la conversazione",
	["Pin conversation"] = "Fissa la conversazione",
	["Unpin conversation"] = "Libera la conversazione",
	["Close conversation"] = "Chiudi la conversazione",
	["Target"] = "Seleziona",
	["Look up"] = "Cerca",
	["Mark as read"] = "Segna come letta",
	["Mark as unread"] = "Segna come da leggere",
	["Copy URL"] = "Copia l'URL",
	["Open in copy box"] = "Apri nella casella di copia",

	-- Finestre di dialogo
	["Copy"] = "Copia",
	["Press Ctrl+C to copy, then Esc to close."] =
		"Premi Ctrl+C per copiare, poi Esc per chiudere.",
	["Press Ctrl+C to copy, or save it to a file."] =
		"Premi Ctrl+C per copiare, oppure salvalo su file.",
	["Save to file"] = "Salva su file",
	["Saved. It is in %s after your next reload or logout."] =
		"Salvato. Lo trovi in %s dopo il prossimo ricaricamento o logout.",
	["That conversation is too large to save."] =
		"Quella conversazione è troppo grande per essere salvata.",
	["There was nothing to save."] = "Non c'era niente da salvare.",
	["Export"] = "Esporta",
	["Format"] = "Formato",
	["Plain text"] = "Testo semplice",
	["BBCode"] = true,
	["Markdown"] = true,
	["CSV"] = true,
	["Clear this conversation?"] = "Cancellare questa conversazione?",
	["Clear all history?"] = "Cancellare tutta la cronologia?",
	["This removes %d stored messages. It cannot be undone."] =
		"Questo elimina %d messaggi salvati. Non si può annullare.",
	["This removes every stored message in %d conversations. It cannot be undone."] =
		"Questo elimina tutti i messaggi salvati in %d conversazioni. Non si può annullare.",
	["Cancel"] = "Annulla",
	["Confirm"] = "Conferma",
	["Delete"] = "Elimina",

	-- Categorie delle impostazioni
	["General"] = "Generale",
	["Appearance"] = "Aspetto",
	["Messages"] = "Messaggi",
	["History"] = "Cronologia",
	["Sounds"] = "Suoni",
	["Notifications"] = "Notifiche",
	["Animations"] = "Animazioni",
	["Tabs"] = "Schede",
	["Windows"] = "Finestre",
	["Combat"] = "Combattimento",
	["Links"] = "Collegamenti",
	["Emoticons"] = "Faccine",
	["Advanced"] = "Avanzate",
	["Search settings"] = "Cerca nelle impostazioni",
	["No settings match your search"] = "Nessuna impostazione corrisponde alla ricerca",
	["Try a shorter word, or clear the search."] =
		"Prova una parola più corta, oppure svuota la ricerca.",
	["Nothing here yet"] = "Qui non c'è ancora niente",

	-- Impostazioni: generale
	["Enable WhatTheWhisper"] = "Attiva WhatTheWhisper",
	["Route whispers into the messenger instead of the default chat frame."] =
		"Porta i sussurri nel messenger invece che nella finestra di chat normale.",
	["Hide whispers from chat frames"] = "Nascondi i sussurri nelle finestre di chat",
	["Whispers still arrive normally, they are just not printed in the chat window."] =
		"I sussurri arrivano comunque, semplicemente non vengono scritti nella finestra di chat.",
	["Open on new whisper"] = "Apri a ogni nuovo sussurro",
	["Show the messenger automatically when someone whispers you."] =
		"Mostra il messenger da solo quando qualcuno ti sussurra.",
	["Auto-switch to new conversations"] = "Passa da solo alle nuove conversazioni",
	["Switching away from what you are reading is off by default."] =
		"Spostarti da quello che stai leggendo è disattivato di serie.",
	["Minimap button"] = "Pulsante sulla minimappa",
	["Show a button on the minimap to toggle the messenger."] =
		"Mostra un pulsante sulla minimappa per aprire e chiudere il messenger.",
	["Keep messenger open in combat"] = "Tieni il messenger aperto in combattimento",

	-- Impostazioni: aspetto
	["Skin"] = "Stile",
	["Font"] = "Carattere",
	["Font size"] = "Dimensione del carattere",
	["Background opacity"] = "Opacità dello sfondo",
	["Corner radius"] = "Raggio degli angoli",
	["Density"] = "Densità",
	["Comfortable"] = "Comoda",
	["Compact"] = "Compatta",
	["Sidebar width"] = "Larghezza della barra laterale",
	["Use class colours"] = "Usa i colori delle classi",
	["Show timestamps"] = "Mostra l'orario",
	["Timestamp format"] = "Formato dell'orario",
	["24 hour"] = "24 ore",
	["12 hour"] = "12 ore",
	["Show avatars"] = "Mostra gli avatar",
	["Avatar style"] = "Stile degli avatar",
	["Automatic"] = "Automatico",
	["Class icon"] = "Icona della classe",
	["Initials"] = "Iniziali",
	["Chat bubbles"] = "Fumetti",
	["Group messages"] = "Raggruppa i messaggi",
	["Collapse consecutive messages from the same player."] =
		"Unisce i messaggi consecutivi dello stesso giocatore.",
	["Show date separators"] = "Mostra i separatori di data",
	["Bubble opacity"] = "Opacità dei fumetti",
	["Message spacing"] = "Spaziatura fra i messaggi",

	-- Impostazioni: disposizione
	["Layout"] = "Disposizione",
	["Sidebar"] = "Barra laterale",
	["Tabbed"] = "A schede",
	["Hybrid"] = "Ibrida",
	["Close tabs after"] = "Chiudi le schede dopo",
	["Never"] = "Mai",
	["%d minutes"] = "%d minuti",
	["Blink unread tabs"] = "Fai lampeggiare le schede da leggere",
	["Open a tab for every conversation"] = "Apri una scheda per ogni conversazione",
	["Snap windows together"] = "Aggancia le finestre fra loro",
	["Lock window position"] = "Blocca la posizione della finestra",
	["Remember window positions"] = "Ricorda la posizione delle finestre",

	-- Impostazioni: cronologia
	["Keep history"] = "Conserva la cronologia",
	["Disabled"] = "Disattivata",
	["This session"] = "Questa sessione",
	["1 day"] = "1 giorno",
	["7 days"] = "7 giorni",
	["30 days"] = "30 giorni",
	["Unlimited"] = "Senza limite",
	["Max messages per conversation"] = "Max messaggi per conversazione",
	["Max conversations"] = "Max conversazioni",
	["Stored messages: %d in %d conversations"] =
		"Messaggi salvati: %d in %d conversazioni",
	["Estimated size: %s"] = "Dimensione stimata: %s",
	["Clear all history"] = "Cancella tutta la cronologia",

	-- Impostazioni: suoni
	["Sound on new message"] = "Suono a ogni nuovo messaggio",
	["Sound when window is hidden"] = "Suono a finestra nascosta",
	["Sound on mention"] = "Suono quando ti nominano",
	["Sound when opening a conversation"] = "Suono all'apertura di una conversazione",
	["Repeat sound cooldown"] = "Attesa fra suoni ripetuti",
	["%d seconds"] = "%d secondi",
	["Do not disturb"] = "Non disturbare",
	["Silence everything until you turn this off."] =
		"Silenzia tutto finché non lo disattivi.",
	["Mute in combat"] = "Silenzia in combattimento",
	["Mute in dungeons"] = "Silenzia nei dungeon",
	["Mute in raids"] = "Silenzia nelle incursioni",
	["Mute in arenas"] = "Silenzia nelle arene",
	["Mute in battlegrounds"] = "Silenzia nei campi di battaglia",
	["None"] = "Nessuno",
	["Custom file"] = "File personale",
	["Sound file path"] = "Percorso del file audio",

	-- Impostazioni: notifiche
	["Show toast notifications"] = "Mostra gli avvisi a comparsa",
	["Toast position"] = "Posizione degli avvisi",
	["Top right"] = "In alto a destra",
	["Top left"] = "In alto a sinistra",
	["Bottom right"] = "In basso a destra",
	["Bottom left"] = "In basso a sinistra",
	["Toast duration"] = "Durata degli avvisi",
	["Flash taskbar icon"] = "Fai lampeggiare l'icona nella barra",
	["Show unread badge"] = "Mostra il contatore dei non letti",
	["Summarise repeated messages"] = "Riassumi i messaggi ripetuti",

	-- Impostazioni: animazioni
	["Animation level"] = "Livello delle animazioni",
	["Off"] = "Spente",
	["Reduced"] = "Ridotte",
	["Normal"] = "Normali",
	["Fancy"] = "Elaborate",
	["Smooth scrolling"] = "Scorrimento fluido",

	-- Impostazioni: combattimento
	["Entering combat"] = "All'inizio del combattimento",
	["Do nothing"] = "Non fare niente",
	["Fade conversations"] = "Sfuma le conversazioni",
	["Minimize conversations"] = "Riduci a icona le conversazioni",
	["Hide conversations"] = "Nascondi le conversazioni",
	["Leaving combat"] = "Alla fine del combattimento",
	["Restore previous state"] = "Ripristina lo stato precedente",
	["Stay hidden"] = "Resta nascosto",
	["Combat fade opacity"] = "Opacità in combattimento",

	-- Impostazioni: collegamenti e faccine
	["Detect links"] = "Riconosci i collegamenti",
	["Highlight links in messages and make them clickable."] =
		"Evidenzia i collegamenti nei messaggi e li rende cliccabili.",
	["Link colour"] = "Colore dei collegamenti",
	["Emoticon style"] = "Stile delle faccine",
	["Text"] = "Testo",
	["Coloured text"] = "Testo colorato",
	["Images"] = "Immagini",
	["Convert raid target markers"] = "Converti i simboli bersaglio",

	-- Impostazioni: avanzate
	["Debug messages"] = "Messaggi di debug",
	["Reset everything"] = "Reimposta tutto",
	["Profile"] = "Profilo",
	["Diagnostics"] = "Diagnostica",
	["Client"] = "Client",
	["Reset window positions"] = "Reimposta la posizione delle finestre",

	-- Selettore di emoji
	["Smileys"] = "Faccine",
	["Symbols"] = "Simboli",
	["Markers"] = "Simboli bersaglio",
	["Recent"] = "Recenti",

	-- Avvisi
	["%s is offline. Message not delivered."] =
		"%s è offline. Messaggio non consegnato.",
	["Message too long, sent as %d parts."] =
		"Messaggio troppo lungo, inviato in %d parti.",

	-- Aiuto dei comandi
	["Commands:"] = "Comandi:",
	["/wtw - toggle the messenger"] = "/wtw - apre o chiude il messenger",
	["Right-click for the list"] = "Clic destro per l'elenco",
	["Mark all as read"] = "Segna tutto come letto",
	["Hide minimap button"] = "Nascondi il pulsante sulla minimappa",
	["/wtw config - open settings"] = "/wtw config - apre le impostazioni",
	["/wtw <name> - open a conversation"] = "/wtw <nome> - apre una conversazione",
	["/wtw clear - clear all history"] = "/wtw clear - cancella tutta la cronologia",
	["/wtw diag - print client diagnostics"] =
		"/wtw diag - mostra la diagnostica del client",

	-- Etichette aggiunte con lo schema delle impostazioni
	["Drop shadows"] = "Ombre",
	["Square"] = "Quadrati",
	["Round"] = "Arrotondati",
	["Always"] = "Sempre",
	["Timestamp on hover"] = "Orario al passaggio del mouse",
	["Maximum toasts"] = "Max avvisi insieme",
	["Show delivery state"] = "Mostra lo stato di consegna",
	["Show whether the server accepted each message you send."] =
		"Mostra se il server ha accettato ogni messaggio che invii.",
	["Mark read when focused"] = "Segna come letta quando è in primo piano",
	["Timestamps"] = "Orario",
	["Reset all settings?"] = "Reimpostare tutte le impostazioni?",
	["Every option goes back to its default. Message history is not touched."] =
		"Ogni opzione torna al valore iniziale. La cronologia dei messaggi non viene toccata.",
	["Reset"] = "Reimposta",
	["Enter a character name"] = "Scrivi il nome di un personaggio",
	["Name"] = "Nome",
	["Open"] = "Apri",
	["Whisper a player"] = "Sussurra a un giocatore",
	["Something went wrong repeatedly, so whispers are being shown in the chat frame again. /wtw debug for details."] =
		"Qualcosa è andato storto più volte, quindi i sussurri tornano nella finestra di chat. /wtw debug per i dettagli.",
	["Whispers here cannot be read by addons, so they are being shown in the chat frame instead."] =
		"Qui gli addon non possono leggere i sussurri, perciò vengono mostrati nella finestra di chat.",
	["Debug logging on."] = "Registro di debug attivo.",
	["Debug logging off."] = "Registro di debug disattivato.",
	["/wtw show / hide - open or close the messenger"] =
		"/wtw show / hide - apre o chiude il messenger",
	["/wtw debug - toggle developer logging"] =
		"/wtw debug - attiva o disattiva il registro di sviluppo",
	["/wtw reset - restore default settings"] =
		"/wtw reset - ripristina le impostazioni iniziali",
	["WhatTheWhisper is ready. Type /wtw to open it."] =
		"WhatTheWhisper è pronto. Scrivi /wtw per aprirlo.",
	["Theme"] = "Tema",
	["Language"] = "Lingua",
	["Independent of the game's own language."] = "Indipendente dalla lingua del gioco.",
	["Typography"] = "Tipografia",
	["Show chat bubbles"] = "Mostra i fumetti",
	["Delivery"] = "Consegna",
	["Mode"] = "Modalità",
	["Nothing logged yet."] = "Non c'è ancora niente nel registro.",
	["/wtw debug log - show the last few entries"] =
		"/wtw debug log - mostra le ultime voci",
	["Open when you start a whisper"] = "Apri quando inizi un sussurro",
	["Typing /w in the default chat box opens that conversation here."] =
		"Scrivere /w nella chat normale apre qui quella conversazione.",
})
