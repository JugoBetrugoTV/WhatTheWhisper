-- WhatTheWhisper -- Français.
--
-- `true` means "the same as the English", written out on purpose: a product
-- name or a format name is not translated, and saying so here is the
-- difference between "we decided" and "somebody forgot the line".

local _, ns = ...

ns.RegisterLocale("frFR", {
	-- Fenêtre
	["WhatTheWhisper"] = true,
	["Conversations"] = "Conversations",
	["Search conversations"] = "Rechercher une conversation",
	["Search messages"] = "Rechercher un message",
	["Character details"] = "Détails du personnage",
	["Class, level, guild, zone and realm under the header."] =
		"Classe, niveau, guilde, zone et royaume sous l'en-tête.",
	["Class"] = "Classe",
	["Race"] = "Race",
	["Guild"] = "Guilde",
	["Zone"] = "Zone",
	["Realm"] = "Royaume",
	["BattleTag"] = true,
	["Character"] = "Personnage",
	["not known"] = "inconnu",
	["Looking up..."] = "Recherche...",
	["Try again in a moment"] = "Réessayez dans un instant",
	["New conversation"] = "Nouvelle conversation",
	["Settings"] = "Réglages",
	["All windows"] = "Toutes les fenêtres",
	["Show every open conversation window side by side."] =
		"Affiche côte à côte toutes les fenêtres de conversation ouvertes.",
	["Click a window to go to it, or press Escape"] =
		"Cliquez sur une fenêtre pour y aller, ou appuyez sur Échap",
	["Minimize"] = "Réduire",
	["Close"] = "Fermer",
	["Maximize"] = "Agrandir",
	["Restore"] = "Restaurer",
	["Pop out"] = "Détacher",
	["Dock"] = "Rattacher",
	["Pin"] = "Épingler",
	["Unpin"] = "Désépingler",
	["Back"] = "Retour",

	-- Rédaction
	["Message %s..."] = "Message à %s...",
	["Type a message..."] = "Écrivez un message...",
	["Send"] = "Envoyer",
	["Emoji"] = "Émoji",
	["%d characters over the limit"] = "%d caractères de trop",
	["Will be sent as %d messages"] = "Sera envoyé en %d messages",

	-- États
	["Today"] = "Aujourd'hui",
	["Yesterday"] = "Hier",
	["Online"] = "En ligne",
	["Offline"] = "Hors ligne",
	["Away"] = "Absent",
	["Busy"] = "Occupé",
	["Muted"] = "Silencieux",
	["Pinned"] = "Épinglé",
	["You"] = "Vous",
	["Delivered"] = "Remis",
	["Sending"] = "Envoi",
	["Not delivered"] = "Non remis",
	["%s is not online"] = "%s n'est pas en ligne",
	["There is no character named %s."] = "Aucun personnage nommé %s.",
	["Character names are 2 to 12 letters, with no spaces, numbers or punctuation."] =
		"Un nom de personnage fait 2 à 12 lettres, sans espace, chiffre ni ponctuation.",
	["That realm name is not valid."] = "Ce nom de royaume n'est pas valide.",
	["A BattleTag looks like Name#1234."] = "Un BattleTag ressemble à Nom#1234.",
	["%d new messages"] = "%d nouveaux messages",
	["1 new message"] = "1 nouveau message",
	["Level %d"] = "Niveau %d",
	["Battle.net"] = true,

	-- États vides
	["No conversations yet"] = "Aucune conversation",
	["Whisper someone to start a conversation."] =
		"Chuchotez à quelqu'un pour commencer une conversation.",
	["Pick a conversation"] = "Choisissez une conversation",
	["Your whispers are kept here, one thread per player."] =
		"Vos chuchotements sont gardés ici, un fil par joueur.",
	["No matches"] = "Aucun résultat",
	["Try a different name or word."] = "Essayez un autre nom ou un autre mot.",
	["Start the conversation"] = "Lancez la conversation",
	["Say hi to %s."] = "Dites bonjour à %s.",
	["History is off"] = "Historique désactivé",
	["Enable it in Settings > History to keep messages."] =
		"Activez-le dans Réglages > Historique pour conserver les messages.",
	["Nothing to show"] = "Rien à afficher",

	-- Menu contextuel
	["Whisper"] = "Chuchoter",
	["Invite to group"] = "Inviter dans le groupe",
	["Add friend"] = "Ajouter en ami",
	["Ignore"] = "Ignorer",
	["Copy name"] = "Copier le nom",
	["Copy message"] = "Copier le message",
	["Copy conversation"] = "Copier la conversation",
	["Export conversation"] = "Exporter la conversation",
	["Clear history"] = "Effacer l'historique",
	["Mute conversation"] = "Mettre en sourdine",
	["Unmute conversation"] = "Réactiver le son",
	["Pin conversation"] = "Épingler la conversation",
	["Unpin conversation"] = "Désépingler la conversation",
	["Close conversation"] = "Fermer la conversation",
	["Target"] = "Cibler",
	["Look up"] = "Rechercher",
	["Mark as read"] = "Marquer comme lu",
	["Mark as unread"] = "Marquer comme non lu",
	["Copy URL"] = "Copier le lien",
	["Open in copy box"] = "Ouvrir dans la boîte de copie",

	-- Dialogues
	["Copy"] = "Copier",
	["Press Ctrl+C to copy, then Esc to close."] =
		"Ctrl+C pour copier, puis Échap pour fermer.",
	["Press Ctrl+C to copy, or save it to a file."] =
		"Ctrl+C pour copier, ou enregistrez dans un fichier.",
	["Save to file"] = "Enregistrer dans un fichier",
	["Saved. It is in %s after your next reload or logout."] =
		"Enregistré. Le fichier sera dans %s après votre prochain rechargement ou déconnexion.",
	["That conversation is too large to save."] =
		"Cette conversation est trop volumineuse pour être enregistrée.",
	["There was nothing to save."] = "Il n'y avait rien à enregistrer.",
	["Export"] = "Exporter",
	["Format"] = "Format",
	["Plain text"] = "Texte brut",
	["BBCode"] = true,
	["Markdown"] = true,
	["CSV"] = true,
	["Clear this conversation?"] = "Effacer cette conversation ?",
	["Clear all history?"] = "Effacer tout l'historique ?",
	["This removes %d stored messages. It cannot be undone."] =
		"Cela supprime %d messages enregistrés. C'est irréversible.",
	["This removes every stored message in %d conversations. It cannot be undone."] =
		"Cela supprime tous les messages enregistrés de %d conversations. C'est irréversible.",
	["Cancel"] = "Annuler",
	["Confirm"] = "Confirmer",
	["Delete"] = "Supprimer",

	-- Catégories de réglages
	["General"] = "Général",
	["Appearance"] = "Apparence",
	["Messages"] = "Messages",
	["History"] = "Historique",
	["Sounds"] = "Sons",
	["Notifications"] = "Notifications",
	["Animations"] = "Animations",
	["Tabs"] = "Onglets",
	["Windows"] = "Fenêtres",
	["Combat"] = "Combat",
	["Links"] = "Liens",
	["Emoticons"] = "Émoticônes",
	["Advanced"] = "Avancé",
	["Search settings"] = "Rechercher un réglage",
	["No settings match your search"] = "Aucun réglage ne correspond",
	["Try a shorter word, or clear the search."] =
		"Essayez un mot plus court, ou effacez la recherche.",
	["Nothing here yet"] = "Rien ici pour l'instant",

	-- Réglages : général
	["Enable WhatTheWhisper"] = "Activer WhatTheWhisper",
	["Route whispers into the messenger instead of the default chat frame."] =
		"Dirige les chuchotements vers la messagerie plutôt que vers la fenêtre de discussion.",
	["Hide whispers from chat frames"] = "Masquer les chuchotements du chat",
	["Whispers still arrive normally, they are just not printed in the chat window."] =
		"Les chuchotements arrivent normalement, ils ne sont simplement plus affichés dans le chat.",
	["Open on new whisper"] = "Ouvrir à la réception",
	["Show the messenger automatically when someone whispers you."] =
		"Affiche la messagerie dès que quelqu'un vous chuchote.",
	["Auto-switch to new conversations"] = "Basculer vers les nouvelles conversations",
	["Switching away from what you are reading is off by default."] =
		"Quitter ce que vous êtes en train de lire est désactivé par défaut.",
	["Minimap button"] = "Bouton de minicarte",
	["Show a button on the minimap to toggle the messenger."] =
		"Affiche un bouton sur la minicarte pour ouvrir la messagerie.",
	["Keep messenger open in combat"] = "Garder la messagerie ouverte en combat",

	-- Réglages : apparence
	["Skin"] = "Thème",
	["Font"] = "Police",
	["Font size"] = "Taille de police",
	["Background opacity"] = "Opacité du fond",
	["Corner radius"] = "Arrondi des coins",
	["Density"] = "Densité",
	["Comfortable"] = "Confortable",
	["Compact"] = "Compacte",
	["Sidebar width"] = "Largeur du panneau",
	["Use class colours"] = "Couleurs de classe",
	["Show timestamps"] = "Afficher l'heure",
	["Timestamp format"] = "Format de l'heure",
	["24 hour"] = "24 heures",
	["12 hour"] = "12 heures",
	["Show avatars"] = "Afficher les avatars",
	["Avatar style"] = "Style d'avatar",
	["Automatic"] = "Automatique",
	["Class icon"] = "Icône de classe",
	["Initials"] = "Initiales",
	["Chat bubbles"] = "Bulles de discussion",
	["Group messages"] = "Grouper les messages",
	["Collapse consecutive messages from the same player."] =
		"Regroupe les messages consécutifs d'un même joueur.",
	["Show date separators"] = "Séparateurs de date",
	["Bubble opacity"] = "Opacité des bulles",
	["Message spacing"] = "Espacement des messages",

	-- Réglages : disposition
	["Layout"] = "Disposition",
	["Sidebar"] = "Panneau latéral",
	["Tabbed"] = "Onglets",
	["Hybrid"] = "Hybride",
	["Close tabs after"] = "Fermer les onglets après",
	["Never"] = "Jamais",
	["%d minutes"] = "%d minutes",
	["Blink unread tabs"] = "Faire clignoter les onglets non lus",
	["Open a tab for every conversation"] = "Un onglet par conversation",
	["Snap windows together"] = "Aimanter les fenêtres",
	["Lock window position"] = "Verrouiller la position",
	["Remember window positions"] = "Mémoriser les positions",

	-- Réglages : historique
	["Keep history"] = "Conserver l'historique",
	["Disabled"] = "Désactivé",
	["This session"] = "Cette session",
	["1 day"] = "1 jour",
	["7 days"] = "7 jours",
	["30 days"] = "30 jours",
	["Unlimited"] = "Illimité",
	["Max messages per conversation"] = "Messages max par conversation",
	["Max conversations"] = "Conversations max",
	["Stored messages: %d in %d conversations"] =
		"Messages enregistrés : %d dans %d conversations",
	["Estimated size: %s"] = "Taille estimée : %s",
	["Clear all history"] = "Effacer tout l'historique",

	-- Réglages : sons
	["Sound on new message"] = "Son à la réception",
	["Sound when window is hidden"] = "Son quand la fenêtre est masquée",
	["Sound on mention"] = "Son quand on vous nomme",
	["Sound when opening a conversation"] = "Son à l'ouverture d'une conversation",
	["Repeat sound cooldown"] = "Délai entre deux sons",
	["%d seconds"] = "%d secondes",
	["Do not disturb"] = "Ne pas déranger",
	["Silence everything until you turn this off."] =
		"Coupe tout jusqu'à ce que vous désactiviez ceci.",
	["Mute in combat"] = "Muet en combat",
	["Mute in dungeons"] = "Muet en donjon",
	["Mute in raids"] = "Muet en raid",
	["Mute in arenas"] = "Muet en arène",
	["Mute in battlegrounds"] = "Muet en champ de bataille",
	["None"] = "Aucun",
	["Custom file"] = "Fichier personnalisé",
	["Sound file path"] = "Chemin du fichier son",

	-- Réglages : notifications
	["Show toast notifications"] = "Afficher les notifications",
	["Toast position"] = "Position des notifications",
	["Top right"] = "En haut à droite",
	["Top left"] = "En haut à gauche",
	["Bottom right"] = "En bas à droite",
	["Bottom left"] = "En bas à gauche",
	["Toast duration"] = "Durée des notifications",
	["Flash taskbar icon"] = "Faire clignoter l'icône",
	["Show unread badge"] = "Afficher le compteur",
	["Summarise repeated messages"] = "Résumer les messages répétés",

	-- Réglages : animations
	["Animation level"] = "Niveau d'animation",
	["Off"] = "Désactivé",
	["Reduced"] = "Réduit",
	["Normal"] = "Normal",
	["Fancy"] = "Soigné",
	["Smooth scrolling"] = "Défilement fluide",

	-- Réglages : combat
	["Entering combat"] = "Entrée en combat",
	["Do nothing"] = "Ne rien faire",
	["Fade conversations"] = "Estomper les conversations",
	["Minimize conversations"] = "Réduire les conversations",
	["Hide conversations"] = "Masquer les conversations",
	["Leaving combat"] = "Sortie de combat",
	["Restore previous state"] = "Restaurer l'état précédent",
	["Stay hidden"] = "Rester masqué",
	["Combat fade opacity"] = "Opacité en combat",

	-- Réglages : liens et émoticônes
	["Detect links"] = "Détecter les liens",
	["Highlight links in messages and make them clickable."] =
		"Met les liens en évidence et les rend cliquables.",
	["Link colour"] = "Couleur des liens",
	["Emoticon style"] = "Style d'émoticônes",
	["Text"] = "Texte",
	["Coloured text"] = "Texte coloré",
	["Images"] = "Images",
	["Convert raid target markers"] = "Convertir les symboles de raid",

	-- Réglages : avancé
	["Debug messages"] = "Messages de débogage",
	["Reset everything"] = "Tout réinitialiser",
	["Profile"] = "Profil",
	["Diagnostics"] = "Diagnostics",
	["Client"] = "Client",
	["Reset window positions"] = "Réinitialiser les positions",

	-- Émojis
	["Smileys"] = "Émoticônes",
	["Symbols"] = "Symboles",
	["Markers"] = "Symboles de raid",
	["Recent"] = "Récents",

	-- Notifications
	["%s is offline. Message not delivered."] = "%s est hors ligne. Message non remis.",
	["Message too long, sent as %d parts."] = "Message trop long, envoyé en %d parties.",

	-- Commandes
	["Commands:"] = "Commandes :",
	["/wtw - toggle the messenger"] = "/wtw - ouvre ou ferme la messagerie",
	["Right-click for the list"] = "Clic droit pour la liste",
	["Mark all as read"] = "Tout marquer comme lu",
	["Hide minimap button"] = "Masquer le bouton de minicarte",
	["/wtw config - open settings"] = "/wtw config - ouvre les réglages",
	["/wtw <name> - open a conversation"] = "/wtw <nom> - ouvre une conversation",
	["/wtw clear - clear all history"] = "/wtw clear - efface tout l'historique",
	["/wtw diag - print client diagnostics"] = "/wtw diag - affiche les diagnostics",

	-- Réglages ajoutés par le schéma
	["Drop shadows"] = "Ombres portées",
	["Square"] = "Carré",
	["Round"] = "Arrondi",
	["Always"] = "Toujours",
	["Timestamp on hover"] = "Heure au survol",
	["Maximum toasts"] = "Notifications maximum",
	["Show delivery state"] = "Afficher l'état de remise",
	["Show whether the server accepted each message you send."] =
		"Indique si le serveur a accepté chacun de vos messages.",
	["Mark read when focused"] = "Marquer comme lu à l'ouverture",
	["Timestamps"] = "Horodatage",
	["Reset all settings?"] = "Réinitialiser tous les réglages ?",
	["Every option goes back to its default. Message history is not touched."] =
		"Chaque option revient à sa valeur par défaut. L'historique n'est pas touché.",
	["Reset"] = "Réinitialiser",
	["Enter a character name"] = "Entrez un nom de personnage",
	["Name"] = "Nom",
	["Open"] = "Ouvrir",
	["Whisper a player"] = "Chuchoter à un joueur",
	["Something went wrong repeatedly, so whispers are being shown in the chat frame again. /wtw debug for details."] =
		"Des erreurs répétées se sont produites : les chuchotements réapparaissent dans la fenêtre de discussion. /wtw debug pour les détails.",
	["Whispers here cannot be read by addons, so they are being shown in the chat frame instead."] =
		"Ici, les chuchotements ne peuvent pas être lus par les addons : ils sont affichés dans la fenêtre de discussion.",
	["Debug logging on."] = "Journalisation activée.",
	["Debug logging off."] = "Journalisation désactivée.",
	["/wtw show / hide - open or close the messenger"] =
		"/wtw show / hide - ouvre ou ferme la messagerie",
	["/wtw debug - toggle developer logging"] = "/wtw debug - active la journalisation",
	["/wtw reset - restore default settings"] = "/wtw reset - restaure les réglages par défaut",
	["WhatTheWhisper is ready. Type /wtw to open it."] =
		"WhatTheWhisper est prêt. Tapez /wtw pour l'ouvrir.",
	["Theme"] = "Thème",
	["Language"] = "Langue",
	["Independent of the game's own language."] = "Indépendant de la langue du jeu.",
	["Typography"] = "Typographie",
	["Show chat bubbles"] = "Afficher les bulles",
	["Delivery"] = "Remise",
	["Mode"] = "Mode",
	["Nothing logged yet."] = "Rien dans le journal.",
	["/wtw debug log - show the last few entries"] =
		"/wtw debug log - affiche les dernières entrées",
	["Open when you start a whisper"] = "Ouvrir quand vous commencez un chuchotement",
	["Typing /w in the default chat box opens that conversation here."] =
		"Taper /w dans la fenêtre de discussion ouvre la conversation ici.",
})
