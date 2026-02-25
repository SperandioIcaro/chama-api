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

  @name_min 2
  @name_max 60

  @doc """
  Changeset de criação:
  - valida nome
  - gera code caso não exista
  - mantém is_active opcional (default do schema)
  """
  def create_changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :is_active])
    |> validate_required([:name])
    |> validate_length(:name, min: @name_min, max: @name_max)
    |> put_code_if_missing()
    |> unique_constraint(:code)
  end

  @doc """
  Changeset de update:
  - permite alterar name e is_active
  - name opcional aqui, mas se vier, valida
  """
  def update_changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :is_active])
    |> validate_length(:name, min: @name_min, max: @name_max)
  end

  defp put_code_if_missing(changeset) do
    case get_field(changeset, :code) do
      nil -> put_change(changeset, :code, gen_code())
      "" -> put_change(changeset, :code, gen_code())
      _ -> changeset
    end
  end

  defp gen_code do
    # curto, humano e único o bastante pra MVP
    Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
  end
end
