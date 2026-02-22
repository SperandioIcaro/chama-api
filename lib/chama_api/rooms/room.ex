defmodule ChamaApi.Rooms.Room do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "rooms" do
    field :name, :string
    field :code, :string
    field :is_active, :boolean, default: true

    belongs_to :created_by, ChamaApi.Accounts.User, foreign_key: :created_by_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(room, attrs) do
    room
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 60)
    |> put_change(:code, gen_code())
    |> unique_constraint(:code)
  end

  def update_changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :is_active])
    |> validate_length(:name, min: 2, max: 60)
  end

  defp gen_code do
    # curto, humano e único o bastante pra MVP
    Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
  end
end
