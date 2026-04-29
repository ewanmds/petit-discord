defmodule MiniDiscord.Salon do
  use GenServer

  def start_link(name) do
    GenServer.start_link(__MODULE__, %{name: name, clients: [], historique: [], password: nil},
      name: via(name))
  end

  def rejoindre(salon, pid), do: rejoindre(salon, pid, nil)
  def rejoindre(salon, pid, password), do: GenServer.call(via(salon), {:rejoindre, pid, password})
  def quitter(salon, pid),   do: GenServer.call(via(salon), {:quitter, pid})
  def broadcast(salon, msg), do: GenServer.cast(via(salon), {:broadcast, msg})
  def definir_password(salon, password), do: GenServer.call(via(salon), {:password, password})

  def lister do
    Registry.select(MiniDiscord.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  def init(state), do: {:ok, state}

  def handle_call({:password, password}, _from, state) do
    hashed_password = :crypto.hash(:sha256, password)
    {:reply, :ok, %{state | password: hashed_password}}
  end

  def handle_call({:rejoindre, pid, password}, _from, state) do
    case verifier_password(state.password, password) do
      :ok ->
        Process.monitor(pid)

        state.historique
        |> Enum.reverse()
        |> Enum.each(fn msg ->
          send(pid, {:message, msg})
        end)

        {:reply, :ok, %{state | clients: [pid | state.clients]}}

      :error ->
        {:reply, {:error, :mot_de_passe_incorrect}, state}
    end
  end

  def handle_call({:rejoindre, pid}, from, state) do
    handle_call({:rejoindre, pid, nil}, from, state)
  end

  def handle_call({:quitter, pid}, _from, state) do
    {:reply, :ok, %{state | clients: List.delete(state.clients, pid)}}
  end

  def handle_cast({:broadcast, msg}, state) do
    Enum.each(state.clients, fn pid ->
      send(pid, {:message, msg})
    end)

    nouveau_historique =
      [msg | state.historique]
      |> Enum.take(10)

    {:noreply, %{state | historique: nouveau_historique}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | clients: List.delete(state.clients, pid)}}
  end

  defp verifier_password(nil, _password), do: :ok

  defp verifier_password(password_hash, password) do
    entered_hash = :crypto.hash(:sha256, password || "")

    if entered_hash == password_hash do
      :ok
    else
      :error
    end
  end

  defp via(name), do: {:via, Registry, {MiniDiscord.Registry, name}}
end
