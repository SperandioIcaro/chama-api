defmodule ChamaApi.Rooms.Participant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "participants" do
    field :role, :string
    field :joined_at, :utc_datetime
    field :left_at, :utc_datetime

    belongs_to :room, ChamaApi.Rooms.Room, type: :binary_id
    belongs_to :user, ChamaApi.Accounts.User, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def create_changeset(participant, attrs) do
    participant
    |> cast(attrs, [:role, :left_at, :room_id, :user_id])
    |> validate_required([:role, :room_id, :user_id])
    |> validate_inclusion(:role, ["host", "member"])
    |> unique_constraint([:room_id, :user_id], name: :participants_room_user_unique)
  end

  def join_changeset(participant, attrs) do
    create_changeset(participant, attrs)
  end
end
