defmodule ChamaApiWeb.RoomController do
  use ChamaApiWeb, :controller

  action_fallback ChamaApiWeb.FallbackController

  alias ChamaApi.Rooms
  alias ChamaApi.Rooms.Room
  alias ChamaApiWeb.Serializers

  # GET /api/rooms — sala geral + salas privadas em que eu estou
  def index(conn, _params) do
    user = current_user(conn)
    rooms = Rooms.list_rooms_for(user)
    counts = Rooms.participant_counts(Enum.map(rooms, & &1.id))

    json(conn, %{
      rooms:
        Enum.map(rooms, fn room ->
          Serializers.room(room,
            user: user,
            participants_count: Map.get(counts, room.id, 0)
          )
        end)
    })
  end

  # GET /api/rooms/general
  def general(conn, _params) do
    user = current_user(conn)
    json(conn, %{room: Serializers.room(Rooms.ensure_general_room(), user: user)})
  end

  def show(conn, %{"id" => id}) do
    user = current_user(conn)

    with {:ok, room} <- fetch_visible_room(id, user) do
      json(conn, %{room: Serializers.room(room, user: user)})
    end
  end

  # POST /api/rooms  { room: { name } } — sempre cria sala privada
  def create(conn, %{"room" => room_params}) when is_map(room_params) do
    user = current_user(conn)

    with {:ok, %Room{} = room} <- Rooms.create_room(room_params, user) do
      conn
      |> put_status(:created)
      |> json(%{
        message: "room_created",
        room: Serializers.room(room, user: user, participants_count: 1)
      })
    end
  end

  def create(_conn, _params), do: {:error, :room_payload_required}

  # PATCH /api/rooms/:id — só o dono
  def update(conn, %{"id" => id} = params) do
    user = current_user(conn)
    attrs = Map.get(params, "room", params)

    with {:ok, room} <- fetch_owned_room(id, user),
         {:ok, %Room{} = room} <- Rooms.update_room(room, attrs) do
      json(conn, %{message: "room_updated", room: Serializers.room(room, user: user)})
    end
  end

  # DELETE /api/rooms/:id — só o dono
  def delete(conn, %{"id" => id}) do
    user = current_user(conn)

    with {:ok, room} <- fetch_owned_room(id, user),
         {:ok, %Room{}} <- Rooms.delete_room(room) do
      json(conn, %{message: "room_deleted"})
    end
  end

  def by_code(conn, %{"code" => code}) do
    user = current_user(conn)

    with {:ok, room} <- Rooms.get_room_by_code_active(code) do
      json(conn, %{room: Serializers.room(room, user: user)})
    end
  end

  # POST /api/rooms/by-code/:code/join
  # Sala privada: quem entra pelo código/link fica "pending" até o admin liberar.
  def join(conn, %{"code" => code}) do
    user = current_user(conn)

    with {:ok, room, participant, event} <- Rooms.join_room_by_code(code, user) do
      if event == :requested, do: notify_owner_of_request(room, user)

      json(conn, %{
        message: if(participant.status == "approved", do: "joined", else: "waiting_approval"),
        status: participant.status,
        room: Serializers.room(room, user: user),
        participant: %{
          id: participant.id,
          role: participant.role,
          user_id: participant.user_id,
          joined_at: participant.joined_at || participant.inserted_at
        }
      })
    end
  end

  # GET /api/rooms/by-code/:code/access — usado para "aguardar aprovação" sem reenviar o pedido
  def access(conn, %{"code" => code}) do
    user = current_user(conn)

    with {:ok, room} <- Rooms.get_room_by_code_active(code) do
      json(conn, %{status: Rooms.access_status(room, user)})
    end
  end

  # GET /api/rooms/by-code/:code/requests — só o admin
  def requests(conn, %{"code" => code}) do
    user = current_user(conn)

    with {:ok, room} <- fetch_owned_by_code(code, user) do
      json(conn, %{requests: Rooms.list_pending_requests(room)})
    end
  end

  def approve_request(conn, %{"code" => code, "user_id" => target}),
    do: resolve_request(conn, code, target, :approve)

  def deny_request(conn, %{"code" => code, "user_id" => target}),
    do: resolve_request(conn, code, target, :deny)

  defp resolve_request(conn, code, target, action) do
    user = current_user(conn)

    with {:ok, room} <- fetch_owned_by_code(code, user),
         {:ok, target_id} <- cast_uuid(target),
         {:ok, _participant} <- apply_request_action(action, room, target_id) do
      event = if action == :approve, do: "join:approved", else: "join:denied"

      ChamaApiWeb.Endpoint.broadcast("user:" <> target_id, event, %{
        room_code: room.code,
        room_name: room.name
      })

      json(conn, %{message: if(action == :approve, do: "approved", else: "denied")})
    end
  end

  defp apply_request_action(:approve, room, target_id), do: Rooms.approve_request(room, target_id)
  defp apply_request_action(:deny, room, target_id), do: Rooms.deny_request(room, target_id)

  defp cast_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :request_not_found}
    end
  end

  defp fetch_owned_by_code(code, user) do
    with {:ok, room} <- Rooms.get_room_by_code_active(code) do
      if room.kind == "private" and Rooms.owner?(room, user),
        do: {:ok, room},
        else: {:error, :forbidden}
    end
  end

  # Avisa o admin em tempo real (canal pessoal), em qualquer tela do app.
  defp notify_owner_of_request(%Room{created_by_id: owner_id} = room, user)
       when is_binary(owner_id) do
    ChamaApiWeb.Endpoint.broadcast("user:" <> owner_id, "join:request", %{
      room_code: room.code,
      room_name: room.name,
      user: Serializers.public_user(user)
    })
  end

  defp notify_owner_of_request(_room, _user), do: :ok

  def leave(conn, %{"code" => code}) do
    user = current_user(conn)

    with {:ok, room} <- Rooms.get_room_by_code_active(code),
         {:ok, _participant} <- Rooms.leave_room(room, user) do
      json(conn, %{message: "left"})
    end
  end

  def participants_by_code(conn, %{"code" => code}) do
    user = current_user(conn)

    with {:ok, room} <- Rooms.get_room_by_code_active(code),
         :ok <- ensure_can_view(room, user) do
      json(conn, %{
        room: %{id: room.id, code: room.code, name: room.name},
        participants: Rooms.list_active_participants(room.id)
      })
    end
  end

  def participants(conn, %{"id" => id}) do
    user = current_user(conn)

    with {:ok, room} <- fetch_visible_room(id, user) do
      json(conn, %{
        room: %{id: room.id, code: room.code, name: room.name},
        participants: Rooms.list_active_participants(room.id)
      })
    end
  end

  # GET /api/rooms/by-code/:code/messages?limit=50
  def messages(conn, %{"code" => code} = params) do
    user = current_user(conn)

    with {:ok, room} <- Rooms.get_room_by_code_active(code),
         :ok <- ensure_can_view(room, user) do
      json(conn, %{messages: Rooms.list_messages(room, parse_limit(params["limit"]))})
    end
  end

  # --------------------
  # helpers
  # --------------------

  defp current_user(conn), do: Guardian.Plug.current_resource(conn)

  defp ensure_can_view(room, user) do
    if Rooms.can_view?(room, user), do: :ok, else: {:error, :forbidden}
  end

  # 404 (e não 403) para salas privadas alheias: não revela que a sala existe.
  defp fetch_visible_room(id, user) do
    with %Room{} = room <- Rooms.get_room(id),
         true <- Rooms.can_view?(room, user) do
      {:ok, room}
    else
      _ -> {:error, :not_found}
    end
  end

  defp fetch_owned_room(id, user) do
    with {:ok, room} <- fetch_visible_room(id, user) do
      if room.kind != "general" and Rooms.owner?(room, user),
        do: {:ok, room},
        else: {:error, :forbidden}
    end
  end

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> 50
    end
  end

  defp parse_limit(_), do: 50
end
