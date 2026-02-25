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

      socket =
        socket
        |> assign(:room_id, room.id)
        |> assign(:room_code, room.code)
        |> assign(:user_id, user.id)

      {:ok, %{room: %{id: room.id, code: room.code}}, socket}
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

  # =========================
  # Signaling (tolerante)
  # =========================

  # Aceita formatos:
  # 1) %{"to" => "user_id", "payload" => %{"sdp" => %{...}}}
  # 2) %{"to" => "user_id", "sdp" => %{...}}
  # 3) %{"payload" => %{"sdp" => %{...}}}  (broadcast)
  # 4) %{"sdp" => %{...}}                 (broadcast)
  @impl true
  # lib/.../room_channel.ex

  def handle_in("chat:new", %{"body" => body, "user_name" => user_name}, socket) do
    body = String.trim(body || "")
    user_name = String.trim(user_name || "")

    if body == "" do
      {:reply, {:error, %{reason: "empty_message"}}, socket}
    else
      user_id = socket.assigns[:user_id] || socket.assigns[:current_user_id] || "anon"

      msg = %{
        "id" => Ecto.UUID.generate(),
        "body" => body,
        "user_id" => user_id,
        "user_name" => user_name,
        "inserted_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      broadcast!(socket, "chat:message", msg)
      {:reply, {:ok, msg}, socket}
    end
  end

  @impl true
  def handle_in("signal:answer", payload, socket) do
    relay_sdp("signal:answer", payload, socket)
  end

  # Aceita formatos:
  # 1) %{"to" => "user_id", "payload" => %{"candidate" => %{...}}}
  # 2) %{"to" => "user_id", "candidate" => %{...}}
  # 3) %{"payload" => %{"candidate" => %{...}}} (broadcast)
  # 4) %{"candidate" => %{...}}                (broadcast)
  @impl true
  def handle_in("signal:ice", payload, socket) do
    relay_candidate("signal:ice", payload, socket)
  end

  @impl true
  def handle_in("signal:hangup", payload, socket) do
    relay_simple("signal:hangup", payload, socket)
  end

  # =========================
  # Helpers
  # =========================

  defp relay_sdp(event, payload, socket) do
    from = socket.assigns.user_id
    to = extract_to(payload)
    sdp = extract_sdp(payload)

    cond do
      is_nil(sdp) ->
        {:reply, {:error, %{reason: "invalid_payload", detail: "missing_sdp"}}, socket}

      not valid_sdp?(sdp) ->
        {:reply, {:error, %{reason: "invalid_payload", detail: "bad_sdp"}}, socket}

      true ->
        broadcast_from!(socket, event, %{
          "from" => from,
          "to" => to,
          "payload" => %{"sdp" => sdp}
        })

        {:reply, {:ok, %{sent: true}}, socket}
    end
  end

  defp relay_candidate(event, payload, socket) do
    from = socket.assigns.user_id
    to = extract_to(payload)
    cand = extract_candidate(payload)

    cond do
      is_nil(cand) ->
        {:reply, {:error, %{reason: "invalid_payload", detail: "missing_candidate"}}, socket}

      not valid_candidate?(cand) ->
        {:reply, {:error, %{reason: "invalid_payload", detail: "bad_candidate"}}, socket}

      true ->
        broadcast_from!(socket, event, %{
          "from" => from,
          "to" => to,
          "payload" => %{"candidate" => cand}
        })

        {:reply, {:ok, %{sent: true}}, socket}
    end
  end

  defp relay_simple(event, payload, socket) do
    from = socket.assigns.user_id
    to = extract_to(payload)

    broadcast_from!(socket, event, %{
      "from" => from,
      "to" => to,
      "payload" => %{}
    })

    {:reply, {:ok, %{sent: true}}, socket}
  end

  # -------------------------
  # Extractors
  # -------------------------

  defp extract_to(%{"to" => to}) when is_binary(to) and byte_size(to) > 0, do: to
  defp extract_to(_), do: nil

  defp extract_sdp(%{"payload" => %{"sdp" => sdp}}), do: sdp
  defp extract_sdp(%{"sdp" => sdp}), do: sdp
  defp extract_sdp(_), do: nil

  defp extract_candidate(%{"payload" => %{"candidate" => cand}}), do: cand
  defp extract_candidate(%{"candidate" => cand}), do: cand
  defp extract_candidate(_), do: nil

  # -------------------------
  # Validators
  # -------------------------

  defp valid_sdp?(%{"type" => type, "sdp" => sdp})
       when is_binary(type) and is_binary(sdp) and byte_size(sdp) > 0,
       do: true

  defp valid_sdp?(_), do: false

  defp valid_candidate?(%{"candidate" => c}) when is_binary(c) and byte_size(c) > 0, do: true
  defp valid_candidate?(_), do: false
end
