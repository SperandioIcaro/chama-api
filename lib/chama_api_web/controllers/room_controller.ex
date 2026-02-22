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

  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, %Room{} = room} <- Rooms.create_room(params, user) do
      conn
      |> put_status(:created)
      |> json(%{message: "room_created", room: room_json(room)})
    end
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
