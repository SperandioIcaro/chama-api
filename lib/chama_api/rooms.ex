defmodule ChamaApi.Rooms do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ChamaApi.Repo
  alias ChamaApi.Rooms.Room
  alias ChamaApi.Rooms.Participant

  # =========================
  # Time helper
  # =========================

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  # =========================
  # Participants helpers
  # =========================

  def get_active_participant(room_id, user_id) do
    Repo.one(
      from p in Participant,
        where:
          p.room_id == ^room_id and
            p.user_id == ^user_id and
            is_nil(p.left_at)
    )
  end

  def list_active_participants(room_id) do
    Repo.all(
      from p in Participant,
        where: p.room_id == ^room_id and is_nil(p.left_at),
        order_by: [asc: p.joined_at]
      # Se você NÃO tiver joined_at no banco, use:
      # order_by: [asc: p.inserted_at]
    )
  end

  # =========================
  # Leave / Join
  # =========================

  def leave_room(%Room{} = room, user) do
    case get_active_participant(room.id, user.id) do
      nil ->
        {:error, :not_in_room}

      %Participant{} = participant ->
        participant
        |> Ecto.Changeset.change(left_at: now())
        |> Repo.update()
    end
  end

  def join_room(%Room{} = room, user) do
    case get_active_participant(room.id, user.id) do
      %Participant{} ->
        {:error, :already_joined}

      nil ->
        # Re-join: se já existe um participant (mesmo "inativo"), reativa
        case Repo.get_by(Participant, room_id: room.id, user_id: user.id) do
          nil ->
            %Participant{}
            |> Participant.create_changeset(%{
              room_id: room.id,
              user_id: user.id,
              role: "member",
              joined_at: now(),
              left_at: nil
            })
            |> Repo.insert()

          %Participant{} = participant ->
            participant
            |> Ecto.Changeset.change(
              left_at: nil,
              joined_at: now(),
              role: participant.role || "member"
            )
            |> Repo.update()
        end
    end
  end

  # Join por code usa o join_room/2 (que reativa quando necessário)
  def join_room_by_code(code, %{} = user) do
    case get_room_by_code(code) do
      nil ->
        {:error, :room_not_found}

      %Room{is_active: false} = room ->
        {:error, :room_inactive, room}

      %Room{} = room ->
        case join_room(room, user) do
          {:ok, participant} ->
            {:ok, room, participant}

          {:error, :already_joined} ->
            {:error, :already_joined}

          {:error, changeset} ->
            {:error, :invalid_participant, changeset}
        end
    end
  end

  # =========================
  # Rooms CRUD
  # =========================

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

  defp maybe_put_creator(changeset, user),
    do: Ecto.Changeset.put_change(changeset, :created_by_id, user.id)
end
