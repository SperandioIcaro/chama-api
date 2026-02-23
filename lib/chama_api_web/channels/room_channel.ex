defmodule ChamaApiWeb.RoomChannel do
  use ChamaApiWeb, :channel

  alias ChamaApiWeb.Presence
  alias ChamaApi.Rooms

  @impl true
  def join("room:" <> code, _payload, socket) do
    user = socket.assigns.current_user

    with {:ok, room} <- Rooms.get_room_by_code_active(code),
         :ok <- Rooms.ensure_participant_active(room.id, user.id) do
      send(self(), {:after_join, room.id, user.id})
      {:ok, %{room: %{id: room.id, code: room.code}}, assign(socket, :room_id, room.id)}
    else
      {:error, :not_found} -> {:error, %{reason: "room_not_found"}}
      {:error, :expired} -> {:error, %{reason: "room_expired"}}
      {:error, :not_participant} -> {:error, %{reason: "not_participant"}}
      other -> {:error, %{reason: "join_failed", detail: inspect(other)}}
    end
  end

  @impl true
  def handle_info({:after_join, room_id, user_id}, socket) do
    Presence.track(socket, "#{user_id}", %{
      user_id: user_id,
      room_id: room_id,
      joined_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # ---------- Signaling ----------

  # Offer
  @impl true
  def handle_in("signal:offer", %{"to" => to, "sdp" => sdp} = payload, socket) do
    relay_sdp("signal:offer", payload, socket, to, sdp)
  end

  # Answer
  @impl true
  def handle_in("signal:answer", %{"to" => to, "sdp" => sdp} = payload, socket) do
    relay_sdp("signal:answer", payload, socket, to, sdp)
  end

  # ICE candidate
  @impl true
  def handle_in("signal:ice", %{"to" => to, "candidate" => cand} = payload, socket) do
    relay_candidate("signal:ice", payload, socket, to, cand)
  end

  # Hangup (opcional)
  @impl true
  def handle_in("signal:hangup", %{"to" => to} = payload, socket) do
    relay_simple("signal:hangup", payload, socket, to)
  end

  # Fallbacks: qualquer formato diferente cai aqui (não crasha, responde limpo)
  @impl true
  def handle_in("signal:offer", _payload, socket),
    do: {:reply, {:error, %{reason: "invalid_payload"}}, socket}

  @impl true
  def handle_in("signal:answer", _payload, socket),
    do: {:reply, {:error, %{reason: "invalid_payload"}}, socket}

  @impl true
  def handle_in("signal:ice", _payload, socket),
    do: {:reply, {:error, %{reason: "invalid_payload"}}, socket}

  @impl true
  def handle_in("signal:hangup", _payload, socket),
    do: {:reply, {:error, %{reason: "invalid_payload"}}, socket}

  # ---------- Helpers ----------

  defp relay_sdp(event, _payload, socket, to, sdp) do
    from = socket.assigns.current_user.id

    cond do
      not is_binary(to) or byte_size(to) == 0 ->
        {:reply, {:error, %{reason: "invalid_payload"}}, socket}

      not valid_sdp?(sdp) ->
        {:reply, {:error, %{reason: "invalid_payload"}}, socket}

      true ->
        broadcast_from!(socket, event, %{
          "from" => from,
          "to" => to,
          "payload" => %{"sdp" => sdp}
        })

        {:reply, {:ok, %{sent: true}}, socket}
    end
  end

  defp relay_candidate(event, _payload, socket, to, cand) do
    from = socket.assigns.current_user.id

    cond do
      not is_binary(to) or byte_size(to) == 0 ->
        {:reply, {:error, %{reason: "invalid_payload"}}, socket}

      not valid_candidate?(cand) ->
        {:reply, {:error, %{reason: "invalid_payload"}}, socket}

      true ->
        broadcast_from!(socket, event, %{
          "from" => from,
          "to" => to,
          "payload" => %{"candidate" => cand}
        })

        {:reply, {:ok, %{sent: true}}, socket}
    end
  end

  defp relay_simple(event, _payload, socket, to) do
    from = socket.assigns.current_user.id

    if is_binary(to) and byte_size(to) > 0 do
      broadcast_from!(socket, event, %{
        "from" => from,
        "to" => to,
        "payload" => %{}
      })

      {:reply, {:ok, %{sent: true}}, socket}
    else
      {:reply, {:error, %{reason: "invalid_payload"}}, socket}
    end
  end

  # Aceita:
  # %{"type" => "offer"/"answer", "sdp" => "..."}
  defp valid_sdp?(%{"type" => type, "sdp" => sdp})
       when is_binary(type) and is_binary(sdp) and byte_size(sdp) > 0,
       do: true

  defp valid_sdp?(_), do: false

  # Aceita:
  # %{"candidate" => "...", "sdpMid" => "...", "sdpMLineIndex" => 0, ...}
  # A única coisa realmente obrigatória é "candidate" string não vazia.
  defp valid_candidate?(%{"candidate" => c}) when is_binary(c) and byte_size(c) > 0, do: true
  defp valid_candidate?(_), do: false
end
