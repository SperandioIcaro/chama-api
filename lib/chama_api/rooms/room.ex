defmodule ChamaApi.Rooms.Room do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds ["general", "private"]

  schema "rooms" do
    field :name, :string
    field :code, :string
    field :is_active, :boolean, default: true
    # "general" (mural aberto, só existe uma) | "private" (entra com convite/código)
    field :kind, :string, default: "private"

    belongs_to :created_by, ChamaApi.Accounts.User, foreign_key: :created_by_id

    timestamps(type: :utc_datetime_usec)
  end

  @name_min 2
  @name_max 60

  def kinds, do: @kinds

  @doc """
  Changeset de criação (sempre sala privada — a sala geral é criada pelo
  sistema, nunca por parâmetros vindos do cliente).
  """
  def create_changeset(room, attrs) do
    room
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: @name_min, max: @name_max)
    |> put_code_if_missing()
    |> unique_constraint(:code)
  end

  def update_changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :is_active])
    |> update_change(:name, &String.trim/1)
    |> validate_length(:name, min: @name_min, max: @name_max)
  end

  defp put_code_if_missing(changeset) do
    case get_field(changeset, :code) do
      nil -> put_change(changeset, :code, gen_code())
      "" -> put_change(changeset, :code, gen_code())
      _ -> changeset
    end
  end

  # 48 bits aleatórios: o código funciona como "link de convite" da sala privada.
  defp gen_code do
    Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
  end
end
