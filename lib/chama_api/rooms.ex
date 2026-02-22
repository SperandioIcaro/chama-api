defmodule ChamaApi.Rooms do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ChamaApi.Repo
  alias ChamaApi.Rooms.Room

  def list_rooms do
    Repo.all(from r in Room, order_by: [desc: r.inserted_at])
  end

  def get_room!(id), do: Repo.get!(Room, id)

  def get_room_by_code(code), do: Repo.get_by(Room, code: code)

  def create_room(attrs, created_by \\ nil) do
    %Room{}
    |> Room.create_changeset(attrs)
    |> maybe_put_creator(created_by)
    |> Repo.insert()
  end

  def update_room(%Room{} = room, attrs) do
    room
    |> Room.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_room(%Room{} = room), do: Repo.delete(room)

  defp maybe_put_creator(changeset, nil), do: changeset
  defp maybe_put_creator(changeset, user), do: Ecto.Changeset.put_change(changeset, :created_by_id, user.id)
end
