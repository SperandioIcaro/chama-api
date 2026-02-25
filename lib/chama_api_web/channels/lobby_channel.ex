defmodule ChamaApiWeb.LobbyChannel do
  use ChamaApiWeb, :channel

  alias ChamaApiWeb.Presence

  @impl true
  def join("lobby:global", _payload, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:error, %{reason: "unauthorized"}}

      user ->
        send(self(), {:after_join, user})
        {:ok, %{message: "joined_lobby"}, assign(socket, :user_id, user.id)}
    end
  end

  @impl true
  def handle_info({:after_join, user}, socket) do
    Presence.track(socket, "#{user.id}", %{
      user_id: user.id,
      online_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # =========================
  # Convites (relay simples)
  # =========================

  @impl true
  def handle_in("invite:send", %{"to" => to, "room_code" => room_code} = _payload, socket)
      when is_binary(to) and is_binary(room_code) do
    from = socket.assigns[:user_id]

    broadcast!(socket, "invite:incoming", %{
      "from" => from,
      "to" => to,
      "room_code" => room_code
    })

    {:reply, {:ok, %{sent: true}}, socket}
  end

  @impl true
  def handle_in("invite:accept", %{"to" => to, "room_code" => room_code}, socket)
      when is_binary(to) and is_binary(room_code) do
    from = socket.assigns[:user_id]

    broadcast!(socket, "invite:accepted", %{
      "from" => from,
      "to" => to,
      "room_code" => room_code
    })

    {:reply, {:ok, %{sent: true}}, socket}
  end

  @impl true
  def handle_in("invite:decline", %{"to" => to, "room_code" => room_code}, socket)
      when is_binary(to) and is_binary(room_code) do
    from = socket.assigns[:user_id]

    broadcast!(socket, "invite:declined", %{
      "from" => from,
      "to" => to,
      "room_code" => room_code
    })

    {:reply, {:ok, %{sent: true}}, socket}
  end

  @impl true
  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "unknown_event"}}, socket}
  end
end
