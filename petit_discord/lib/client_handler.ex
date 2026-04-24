defmodule MiniDiscord.ClientHandler do
  require Logger

  def start(socket) do
    :gen_tcp.send(socket, "Bienvenue sur MiniDiscord!\r\n")

    case choisir_pseudo(socket) do
      {:ok, pseudo} ->
        :gen_tcp.send(socket, "Salons disponibles : #{salons_dispo()}\r\n")
        :gen_tcp.send(socket, "Rejoins un salon (ex: general) : ")

        case :gen_tcp.recv(socket, 0) do
          {:ok, salon_brut} ->
            salon = String.trim(salon_brut)
            rejoindre_salon(socket, pseudo, salon)

          {:error, reason} ->
            Logger.info("Client déconnecté avant choix du salon : #{inspect(reason)}")
            liberer_pseudo(pseudo)
        end

      {:error, reason} ->
        Logger.info("Client déconnecté avant choix du pseudo : #{inspect(reason)}")
    end
  end

  defp choisir_pseudo(socket) do
    :gen_tcp.send(socket, "Entre ton pseudo : ")

    case :gen_tcp.recv(socket, 0) do
      {:ok, pseudo_brut} ->
        pseudo = String.trim(pseudo_brut)

        cond do
          pseudo == "" ->
            :gen_tcp.send(socket, "Pseudo vide interdit.\r\n")
            choisir_pseudo(socket)

          reserver_pseudo_atomique(pseudo) ->
            {:ok, pseudo}

          true ->
            :gen_tcp.send(socket, "Pseudo deja pris, essaie encore.\r\n")
            choisir_pseudo(socket)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp rejoindre_salon(socket, pseudo, salon) do
    case Registry.lookup(MiniDiscord.Registry, salon) do
      [] ->
        DynamicSupervisor.start_child(
          MiniDiscord.SalonSupervisor,
          {MiniDiscord.Salon, salon}
        )

      _ ->
        :ok
    end

    MiniDiscord.Salon.rejoindre(salon, self())
    MiniDiscord.Salon.broadcast(salon, "📢 #{pseudo} a rejoint ##{salon}\r\n")
    :gen_tcp.send(socket, "Tu es dans ##{salon} — écris tes messages !\r\n")

    loop(socket, pseudo, salon)
  end

  defp loop(socket, pseudo, salon) do
    receive do
      {:message, msg} ->
        :gen_tcp.send(socket, msg)
    after
      0 -> :ok
    end

    case :gen_tcp.recv(socket, 0, 100) do
      {:ok, msg} ->
        msg = String.trim(msg)

        case gerer_commande(socket, pseudo, salon, msg) do
          {:continue, nouveau_salon} ->
            loop(socket, pseudo, nouveau_salon)

          :quit ->
            Logger.info("Client #{pseudo} a quitté via /quit")
            MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
            MiniDiscord.Salon.quitter(salon, self())
            liberer_pseudo(pseudo)
        end

      {:error, :timeout} ->
        loop(socket, pseudo, salon)

      {:error, reason} ->
        Logger.info("Client déconnecté : #{inspect(reason)}")
        MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
        MiniDiscord.Salon.quitter(salon, self())
        liberer_pseudo(pseudo)
    end
  end

  defp gerer_commande(socket, pseudo, salon, msg) do
    case msg do
      "/list" ->
        salons = MiniDiscord.Salon.lister()
        liste = Enum.join(salons, ", ")
        :gen_tcp.send(socket, "📋 Salons actifs: #{liste}\r\n")
        {:continue, salon}

      "/join " <> nouveau_salon ->
        nouveau_salon = String.trim(nouveau_salon)

        cond do
          nouveau_salon == "" ->
            :gen_tcp.send(socket, "Usage: /join <nom_salon>\r\n")
            {:continue, salon}

          nouveau_salon == salon ->
            :gen_tcp.send(socket, "Tu es déjà dans ##{salon}\r\n")
            {:continue, salon}

          true ->
            MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
            MiniDiscord.Salon.quitter(salon, self())

            case Registry.lookup(MiniDiscord.Registry, nouveau_salon) do
              [] ->
                DynamicSupervisor.start_child(
                  MiniDiscord.SalonSupervisor,
                  {MiniDiscord.Salon, nouveau_salon}
                )

              _ ->
                :ok
            end

            MiniDiscord.Salon.rejoindre(nouveau_salon, self())
            MiniDiscord.Salon.broadcast(nouveau_salon, "📢 #{pseudo} a rejoint ##{nouveau_salon}\r\n")
            :gen_tcp.send(socket, "Tu es passé dans ##{nouveau_salon}\r\n")
            {:continue, nouveau_salon}
        end

      "/quit" ->
        :quit

      "/help" ->
        :gen_tcp.send(socket, "Commandes disponibles:\r\n")
        :gen_tcp.send(socket, "  /list       - Lister les salons\r\n")
        :gen_tcp.send(socket, "  /join <nom> - Rejoindre un salon\r\n")
        :gen_tcp.send(socket, "  /quit       - Quitter le serveur\r\n")
        :gen_tcp.send(socket, "  /help       - Afficher cette aide\r\n")
        {:continue, salon}

      "/" <> _ ->
        :gen_tcp.send(socket, "❌ Commande inconnue. Tape /help pour la liste des commandes.\r\n")
        {:continue, salon}

      _ ->
        MiniDiscord.Salon.broadcast(salon, "[#{pseudo}] #{msg}\r\n")
        {:continue, salon}
    end
  end

  defp salons_dispo do
    case MiniDiscord.Salon.lister() do
      [] -> "aucun (tu seras le premier !)"
      salons -> Enum.join(salons, ", ")
    end
  end

  defp reserver_pseudo_atomique(pseudo) do
    :ets.insert_new(:pseudos, {pseudo, self()})
  end

  defp liberer_pseudo(pseudo) do
    case :ets.lookup(:pseudos, pseudo) do
      [{^pseudo, pid}] when pid == self() ->
        :ets.delete(:pseudos, pseudo)

      _ ->
        :ok
    end
  end
end
