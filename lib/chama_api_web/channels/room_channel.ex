defmodule ChamaApiWeb.RoomChannel do
  @moduledoc """
  Canal de uma sala: chat persistido, presença e sinalização WebRTC (malha/mesh).

  Fluxo da chamada: quem entra manda `call:join`, recebe a lista de quem já
  está na chamada e envia uma `offer` (com `to`) para cada um. Quem já estava
  só responde. Todo sinal tem `to`, e o servidor só entrega ao destinatário.
  """

  use ChamaApiWeb, :channel

  alias ChamaApi.Rooms
  alias ChamaApi.Rooms.Room
  alias ChamaApiWeb.{Presence, Serializers}

  # Chamada em malha: cada pessoa abre uma conexão com cada outra. Acima disso
  # o ideal é um SFU (LiveKit, mediasoup...).
  @max_call_peers 5
  @min_chat_interval_ms 300

  # Prazo (segundos) da permissão de apresentar dada pelo admin.
  @share_salt "chama:share_grant"
  @share_grant_ttl 300

  intercept [
    "signal:offer",
    "signal:answer",
    "signal:ice",
    "signal:hangup",
    "share:requested",
    "share:granted",
    "share:denied",
    "share:revoked"
  ]

  @impl true
  def join("room:" <> code, _payload, %{assigns: %{current_user: user}} = socket) do
    with {:ok, room} <- Rooms.get_room_by_code_active(code),
         :ok <- ensure_member(room, user) do
      send(self(), {:after_join, room, user})

      socket =
        socket
        |> assign(:room, room)
        |> assign(:user_id, user.id)

      {:ok, %{room: Serializers.room(room)}, socket}
    else
      {:error, reason} when is_atom(reason) -> {:error, %{reason: Atom.to_string(reason)}}
      _ -> {:error, %{reason: "join_failed"}}
    end
  end

  def join(_topic, _payload, _socket), do: {:error, %{reason: "unauthorized"}}

  # A sala geral é aberta: abrir o mural já te coloca como participante.
  defp ensure_member(%Room{kind: "general"} = room, user) do
    case Rooms.join_room(room, user) do
      {:ok, _participant} -> :ok
      {:error, _} -> {:error, :join_failed}
    end
  end

  defp ensure_member(%Room{} = room, user), do: Rooms.ensure_participant_active(room.id, user.id)

  @impl true
  def handle_info({:after_join, room, user}, socket) do
    {:ok, _} =
      Presence.track(socket, user.id, %{
        name: user.name,
        avatar_url: user.avatar_url,
        room_id: room.id,
        in_call: false,
        sharing: false,
        screen_stream_id: nil,
        joined_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # =========================
  # Chat
  # =========================

  @impl true
  def handle_in("chat:new", %{"body" => body}, socket) when is_binary(body) do
    # monotonic_time pode ser negativo (ponto de partida arbitrário), então o
    # "nunca enviou" é `nil` e não 0 — com 0, a primeira mensagem já era recusada.
    now = System.monotonic_time(:millisecond)
    last = socket.assigns[:last_chat_at]

    if is_integer(last) and now - last < @min_chat_interval_ms do
      {:reply, {:error, %{reason: "slow_down"}}, socket}
    else
      # Nome e avatar vêm do servidor (o cliente não pode se passar por outro).
      case Rooms.create_message(socket.assigns.room, socket.assigns.current_user, body) do
        {:ok, message} ->
          broadcast!(socket, "chat:message", message)
          {:reply, {:ok, %{id: message.id}}, assign(socket, :last_chat_at, now)}

        {:error, _changeset} ->
          {:reply, {:error, %{reason: "invalid_message"}}, socket}
      end
    end
  end

  # =========================
  # Chamada de vídeo
  # =========================

  def handle_in("call:join", _payload, %{assigns: %{room: %Room{kind: "general"}}} = socket) do
    {:reply, {:error, %{reason: "no_calls_in_general"}}, socket}
  end

  def handle_in("call:join", _payload, socket) do
    me = socket.assigns.user_id
    peers = call_peer_ids(socket, me)

    if length(peers) >= @max_call_peers do
      {:reply, {:error, %{reason: "call_full"}}, socket}
    else
      set_in_call(socket, me, true)
      {:reply, {:ok, %{peers: peers}}, socket}
    end
  end

  # Estado de microfone/câmera (para os outros mostrarem o avatar quando a câmera está off).
  def handle_in("call:media", %{"mic" => mic, "cam" => cam}, socket)
      when is_boolean(mic) and is_boolean(cam) do
    Presence.update(socket, socket.assigns.user_id, fn meta ->
      meta |> Map.put(:mic, mic) |> Map.put(:cam, cam)
    end)

    {:reply, {:ok, %{}}, socket}
  end

  def handle_in("call:leave", _payload, socket) do
    me = socket.assigns.user_id
    set_in_call(socket, me, false)
    set_sharing(socket, me, false, nil)
    {:reply, {:ok, %{}}, socket}
  end

  # =========================
  # Apresentação de tela (precisa da permissão do admin)
  # =========================
  #
  # Fluxo: `share:request` → o admin recebe `share:requested` → `share:approve` gera um
  # token assinado só para aquela pessoa → ela escolhe a tela e manda `share:start` com o token.
  # Só uma pessoa apresenta por vez. O admin não precisa de permissão e pode `share:revoke`.

  def handle_in("share:request", _payload, %{assigns: %{room: %Room{kind: "general"}}} = socket),
    do: reply_error(socket, "no_calls_in_general")

  def handle_in("share:request", _payload, socket) do
    me = socket.assigns.user_id
    room = socket.assigns.room

    cond do
      not in_call?(socket, me) ->
        reply_error(socket, "not_in_call")

      someone_sharing?(socket) ->
        reply_error(socket, "someone_sharing")

      owner_id?(room, me) ->
        {:reply, {:ok, %{granted: true}}, socket}

      not present?(socket, room.created_by_id) ->
        reply_error(socket, "admin_not_in_room")

      true ->
        broadcast_from!(socket, "share:requested", %{
          "from" => me,
          "to" => room.created_by_id,
          "name" => socket.assigns.current_user.name
        })

        {:reply, {:ok, %{granted: false}}, socket}
    end
  end

  def handle_in("share:approve", %{"user_id" => target}, socket),
    do: decide_share("share:granted", target, socket)

  def handle_in("share:deny", %{"user_id" => target}, socket),
    do: decide_share("share:denied", target, socket)

  def handle_in("share:revoke", %{"user_id" => target}, socket),
    do: decide_share("share:revoked", target, socket)

  def handle_in("share:start", %{"stream_id" => stream_id} = payload, socket)
      when is_binary(stream_id) and byte_size(stream_id) in 1..200 do
    me = socket.assigns.user_id
    room = socket.assigns.room

    cond do
      room.kind == "general" ->
        reply_error(socket, "no_calls_in_general")

      not in_call?(socket, me) ->
        reply_error(socket, "not_in_call")

      someone_sharing?(socket) ->
        reply_error(socket, "someone_sharing")

      not (owner_id?(room, me) or valid_grant?(room, me, payload["token"])) ->
        reply_error(socket, "not_allowed")

      true ->
        set_sharing(socket, me, true, stream_id)
        {:reply, {:ok, %{}}, socket}
    end
  end

  def handle_in("share:stop", _payload, socket) do
    set_sharing(socket, socket.assigns.user_id, false, nil)
    {:reply, {:ok, %{}}, socket}
  end

  # =========================
  # Sinalização WebRTC (sempre com `to`)
  # =========================

  def handle_in("signal:offer", payload, socket), do: relay_sdp("signal:offer", payload, socket)
  def handle_in("signal:answer", payload, socket), do: relay_sdp("signal:answer", payload, socket)
  def handle_in("signal:ice", payload, socket), do: relay_candidate("signal:ice", payload, socket)
  def handle_in("signal:hangup", payload, socket), do: relay_simple("signal:hangup", payload, socket)

  def handle_in(_event, _payload, socket), do: {:reply, {:error, %{reason: "unknown_event"}}, socket}

  # Entrega o sinal só ao destinatário (`to`); os outros processos do canal descartam.
  @impl true
  def handle_out(event, %{"to" => to} = payload, socket) when is_binary(to) do
    if to == socket.assigns.user_id, do: push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_out(_event, _payload, socket), do: {:noreply, socket}

  # -------------------------
  # Helpers
  # -------------------------

  defp reply_error(socket, reason), do: {:reply, {:error, %{reason: reason}}, socket}

  defp owner_id?(%Room{created_by_id: owner}, id), do: is_binary(owner) and owner == id

  defp presence_metas(socket, id) do
    case Map.get(Presence.list(socket), id) do
      %{metas: metas} -> metas
      _ -> []
    end
  end

  defp present?(socket, id), do: presence_metas(socket, id) != []
  defp in_call?(socket, id), do: Enum.any?(presence_metas(socket, id), & &1[:in_call])

  defp someone_sharing?(socket) do
    socket
    |> Presence.list()
    |> Enum.any?(fn {_id, %{metas: metas}} -> Enum.any?(metas, & &1[:sharing]) end)
  end

  defp set_sharing(socket, user_id, sharing, stream_id) do
    Presence.update(socket, user_id, fn meta ->
      meta |> Map.put(:sharing, sharing) |> Map.put(:screen_stream_id, stream_id)
    end)
  end

  # Só o admin decide; a decisão chega apenas ao destinatário (`to`).
  defp decide_share(event, target, socket) do
    room = socket.assigns.room

    with true <- owner_id?(room, socket.assigns.user_id),
         {:ok, target_id} <- Ecto.UUID.cast(target) do
      payload = %{"from" => socket.assigns.user_id, "to" => target_id}

      payload =
        if event == "share:granted" do
          token =
            Phoenix.Token.sign(ChamaApiWeb.Endpoint, @share_salt, %{
              room_id: room.id,
              user_id: target_id
            })

          Map.put(payload, "token", token)
        else
          payload
        end

      broadcast_from!(socket, event, payload)
      {:reply, {:ok, %{}}, socket}
    else
      _ -> reply_error(socket, "not_allowed")
    end
  end

  defp valid_grant?(room, user_id, token) when is_binary(token) do
    case Phoenix.Token.verify(ChamaApiWeb.Endpoint, @share_salt, token, max_age: @share_grant_ttl) do
      {:ok, %{room_id: rid, user_id: uid}} -> rid == room.id and uid == user_id
      _ -> false
    end
  end

  defp valid_grant?(_room, _user_id, _token), do: false

  defp set_in_call(socket, user_id, value) do
    Presence.update(socket, user_id, &Map.put(&1, :in_call, value))
  end

  defp call_peer_ids(socket, me) do
    socket
    |> Presence.list()
    |> Enum.filter(fn {id, %{metas: metas}} -> id != me and Enum.any?(metas, & &1[:in_call]) end)
    |> Enum.map(fn {id, _} -> id end)
  end

  defp relay_sdp(event, payload, socket) do
    with {:ok, to} <- fetch_to(payload),
         {:ok, sdp} <- fetch_sdp(payload) do
      broadcast_from!(socket, event, %{
        "from" => socket.assigns.user_id,
        "to" => to,
        "payload" => %{"sdp" => sdp}
      })

      {:reply, {:ok, %{sent: true}}, socket}
    else
      {:error, reason} -> {:reply, {:error, %{reason: "invalid_payload", detail: reason}}, socket}
    end
  end

  defp relay_candidate(event, payload, socket) do
    with {:ok, to} <- fetch_to(payload),
         {:ok, candidate} <- fetch_candidate(payload) do
      broadcast_from!(socket, event, %{
        "from" => socket.assigns.user_id,
        "to" => to,
        "payload" => %{"candidate" => candidate}
      })

      {:reply, {:ok, %{sent: true}}, socket}
    else
      {:error, reason} -> {:reply, {:error, %{reason: "invalid_payload", detail: reason}}, socket}
    end
  end

  defp relay_simple(event, payload, socket) do
    case fetch_to(payload) do
      {:ok, to} ->
        broadcast_from!(socket, event, %{
          "from" => socket.assigns.user_id,
          "to" => to,
          "payload" => %{}
        })

        {:reply, {:ok, %{sent: true}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: "invalid_payload", detail: reason}}, socket}
    end
  end

  defp fetch_to(%{"to" => to}) when is_binary(to) do
    case Ecto.UUID.cast(to) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, "bad_to"}
    end
  end

  defp fetch_to(_), do: {:error, "missing_to"}

  defp fetch_sdp(%{"sdp" => %{"type" => type, "sdp" => sdp} = desc})
       when is_binary(type) and is_binary(sdp) and byte_size(sdp) > 0,
       do: {:ok, desc}

  defp fetch_sdp(_), do: {:error, "bad_sdp"}

  defp fetch_candidate(%{"candidate" => %{"candidate" => c} = cand})
       when is_binary(c) and byte_size(c) > 0,
       do: {:ok, cand}

  defp fetch_candidate(_), do: {:error, "bad_candidate"}
end
