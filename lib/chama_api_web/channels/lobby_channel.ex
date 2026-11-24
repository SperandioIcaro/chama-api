defmodule ChamaApiWeb.LobbyChannel do
  @moduledoc """
  Presença global ("quem está online") + envio de convites.

  O convite NÃO é mais broadcast para todo mundo: o servidor valida quem está
  convidando e entrega só no canal pessoal (`user:<id>`) de quem foi convidado.
  """

  use ChamaApiWeb, :channel

  alias ChamaApi.Rooms
  alias ChamaApiWeb.{Presence, Serializers}

  @impl true
  def join("lobby:global", _payload, %{assigns: %{current_user: user}} = socket) do
    send(self(), {:after_join, user})
    {:ok, %{message: "joined_lobby"}, socket}
  end

  def join(_topic, _payload, _socket), do: {:error, %{reason: "unauthorized"}}

  @impl true
  def handle_info({:after_join, user}, socket) do
    {:ok, _} =
      Presence.track(socket, user.id, %{
        name: user.name,
        avatar_url: user.avatar_url,
        online_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # =========================
  # Convites
  # =========================

  @impl true
  def handle_in("invite:send", %{"to" => to, "room_code" => code}, socket)
      when is_binary(to) and is_binary(code) do
    me = socket.assigns.current_user

    with {:ok, to_id} <- Ecto.UUID.cast(to),
         true <- to_id != me.id,
         %{kind: "private", is_active: true} = room <- Rooms.get_room_by_code(code),
         :ok <- Rooms.ensure_participant_active(room.id, me.id),
         {:ok, _participant} <- Rooms.invite_user(room, to_id) do
      ChamaApiWeb.Endpoint.broadcast("user:" <> to_id, "invite:incoming", %{
        from: Serializers.public_user(me),
        room_code: room.code,
        room_name: room.name
      })

      {:reply, {:ok, %{sent: true}}, socket}
    else
      {:error, :already_member} -> {:reply, {:error, %{reason: "already_member"}}, socket}
      _ -> {:reply, {:error, %{reason: "invalid_invite"}}, socket}
    end
  end

  def handle_in("invite:accept", payload, socket), do: relay_answer("invite:accepted", payload, socket)

  def handle_in("invite:decline", %{"room_code" => code} = payload, socket) when is_binary(code) do
    # recusou: o pré-acesso do convite deixa de valer
    with %{} = room <- Rooms.get_room_by_code(code) do
      Rooms.revoke_invite(room, socket.assigns.current_user)
    end

    relay_answer("invite:declined", payload, socket)
  end

  def handle_in(_event, _payload, socket), do: {:reply, {:error, %{reason: "unknown_event"}}, socket}

  # Avisa só quem convidou.
  defp relay_answer(event, %{"to" => to, "room_code" => code}, socket)
       when is_binary(to) and is_binary(code) do
    case Ecto.UUID.cast(to) do
      {:ok, to_id} ->
        ChamaApiWeb.Endpoint.broadcast("user:" <> to_id, event, %{
          from: Serializers.public_user(socket.assigns.current_user),
          room_code: code
        })

        {:reply, {:ok, %{sent: true}}, socket}

      :error ->
        {:reply, {:error, %{reason: "invalid_invite"}}, socket}
    end
  end

  defp relay_answer(_event, _payload, socket), do: {:reply, {:error, %{reason: "invalid_invite"}}, socket}
end
