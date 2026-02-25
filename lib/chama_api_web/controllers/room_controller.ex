defmodule ChamaApiWeb.RoomController do
  use ChamaApiWeb, :controller

  action_fallback ChamaApiWeb.FallbackController

  alias ChamaApi.Rooms
  alias ChamaApi.Rooms.Room

  def index(conn, _params) do
    rooms = Rooms.list_rooms()

    json(conn, %{
      rooms: Enum.map(rooms, &room_json/1)
    })
  end

  def show(conn, %{"id" => id}) do
    room = Rooms.get_room!(id)
    json(conn, %{room: room_json(room)})
  end

  def create(conn, %{"room" => room_params}) do
    case Guardian.Plug.current_resource(conn) do
      nil ->
        unauthorized(conn)

      user ->
        with {:ok, %Room{} = room} <- Rooms.create_room(room_params, user) do
          conn
          |> put_status(:created)
          |> json(%{message: "room_created", room: room_json(room)})
        end
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: "validation_error",
      message: "Alguns campos estão inválidos. Corrija e tente novamente.",
      status: 422,
      fields: %{room: ["é obrigatório (envie no formato { room: { name: \"...\" } })"]},
      how_to_fix: "Envie o payload no formato correto."
    })
  end

  def update(conn, %{"id" => id} = params) do
    room = Rooms.get_room!(id)

    with {:ok, %Room{} = room} <- Rooms.update_room(room, Map.drop(params, ["id"])) do
      json(conn, %{message: "room_updated", room: room_json(room)})
    end
  end

  def delete(conn, %{"id" => id}) do
    room = Rooms.get_room!(id)

    with {:ok, %Room{}} <- Rooms.delete_room(room) do
      json(conn, %{message: "room_deleted"})
    end
  end

  def by_code(conn, %{"code" => code}) do
    case Rooms.get_room_by_code(code) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{
          error: "room_not_found",
          message: "Nenhuma sala encontrada com esse código.",
          status: 404,
          how_to_fix: "Confira o código e tente novamente."
        })

      %Room{} = room ->
        if room.is_active do
          json(conn, %{room: room_json(room)})
        else
          conn
          |> put_status(:gone)
          |> json(%{
            error: "room_inactive",
            message: "Essa sala existe, mas está desativada.",
            status: 410,
            how_to_fix: "Peça para o criador reativar ou crie uma nova sala."
          })
        end
    end
  end

  def join(conn, %{"code" => code}) do
    case Guardian.Plug.current_resource(conn) do
      nil ->
        unauthorized(conn)

      user ->
        case Rooms.join_room_by_code(code, user) do
          {:ok, room, participant} ->
            joined_at =
              cond do
                Map.has_key?(participant, :joined_at) and not is_nil(participant.joined_at) ->
                  participant.joined_at

                Map.has_key?(participant, :inserted_at) and not is_nil(participant.inserted_at) ->
                  participant.inserted_at

                true ->
                  DateTime.utc_now()
              end

            json(conn, %{
              message: "joined",
              room: room_json(room),
              participant: %{
                id: participant.id,
                role: participant.role,
                user_id: participant.user_id,
                joined_at: joined_at
              }
            })

          {:error, :room_not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{
              error: "room_not_found",
              message: "Nenhuma sala encontrada com esse código.",
              status: 404,
              how_to_fix: "Confira o código e tente novamente."
            })

          {:error, :room_inactive, _room} ->
            conn
            |> put_status(:gone)
            |> json(%{
              error: "room_inactive",
              message: "Essa sala existe, mas está desativada.",
              status: 410,
              how_to_fix: "Peça para o criador reativar ou crie uma nova sala."
            })

          {:error, :already_joined, _changeset} ->
            conn
            |> put_status(:conflict)
            |> json(%{
              error: "already_joined",
              message: "Você já está nessa sala.",
              status: 409,
              how_to_fix:
                "Se quiser entrar de novo, implemente um endpoint de sair (leave) e tente novamente."
            })
        end
    end
  end

  def leave(conn, %{"code" => code}) do
    case Guardian.Plug.current_resource(conn) do
      nil ->
        unauthorized(conn)

      user ->
        with %Room{} = room <- Rooms.get_room_by_code(code),
             true <- room.is_active || {:error, :room_inactive},
             {:ok, _participant} <- Rooms.leave_room(room, user) do
          json(conn, %{message: "left"})
        else
          nil ->
            conn |> put_status(:not_found) |> json(%{error: "room_not_found"})

          {:error, :room_inactive} ->
            conn |> put_status(:gone) |> json(%{error: "room_inactive"})

          {:error, :not_in_room} ->
            conn |> put_status(:conflict) |> json(%{error: "not_in_room"})
        end
    end
  end

  def participants_by_code(conn, %{"code" => code}) do
    with %Room{} = room <- Rooms.get_room_by_code(code) do
      participants = Rooms.list_active_participants(room.id)

      json(conn, %{
        room: %{id: room.id, code: room.code, name: room.name},
        participants:
          Enum.map(participants, fn p ->
            joined_at =
              cond do
                Map.has_key?(p, :joined_at) and not is_nil(p.joined_at) -> p.joined_at
                Map.has_key?(p, :inserted_at) and not is_nil(p.inserted_at) -> p.inserted_at
                true -> nil
              end

            %{
              id: p.id,
              user_id: p.user_id,
              role: p.role,
              joined_at: joined_at
            }
          end)
      })
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "room_not_found"})
    end
  end

  # --------------------
  # helpers
  # --------------------
  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{
      error: "unauthorized",
      message: "Você precisa estar autenticado para fazer isso.",
      status: 401,
      how_to_fix: "Envie o token JWT no header Authorization: Bearer <token>."
    })
  end

  defp room_json(room) do
    %{
      id: room.id,
      name: room.name,
      code: room.code,
      is_active: room.is_active,
      created_by_id: room.created_by_id,
      inserted_at: room.inserted_at
    }
  end
end
