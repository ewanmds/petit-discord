# PetitDiscord

#Q1 On utilise Process.monitor/1 dans handle_call({:rejoindre, pid}, ...) 
    afin que le salon soit notifié automatiquement si ce client meurt par exexmple par un crash, fermeture ou kill du processus, le genServeur reçoit alors un message {:DOWN, ...} et peut retirer ce pid de sa liste sans attendre un quitter explicite.

#Q2 Si handle_info({:DOWN, ...}) n’est pas implémenté alors les clients 
    morts restent dans l'état du salon, ce sont des PID fantomes, ducoup l'état est incohérent, le salon tente de broadcaster vers des processus inexsitants et les messages :DOWN non gérés peuvent généré du bruits(logs).
  
#Q3 handle_call est synchrone car l'appelant attent une réponse ({:reply, ...}), alors que handle_cast est asyncrhrone, il n'attent pas de réponse ({:noreply, ...}).

Boradcast est un cast car l'on veut juste déclencher l'evoie du message à tous sans bloquer l'émetteur ni lui retourner une valeur.

#2-4 Oui, le salon redémarre après le kill. C’est parce qu’il est démarré comme enfant du superviseur dans lib/petit_discord.ex, via le DynamicSupervisor nommé MiniDiscord.SalonSupervisor. Quand on tu le processus du salon, le superviseur détecte sa mort et le relance automatiquement. Le salon repart avec un nouvel état en mémoire, donc sa liste de clients est réinitialisée.

#2-5 La stratégie one_for_one redémarre uniquement le processus qui a planté.
    La stratégie one_for_all redémarre tous les enfanst des supervisseurs dèq qu'un seul tombe.


