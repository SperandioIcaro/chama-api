defmodule ChamaApi.Rooms.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_length 1000

  schema "messages" do
    field :body, :string

    belongs_to :room, ChamaApi.Rooms.Room
    belongs_to :user, ChamaApi.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def max_length, do: @max_length

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: @max_length)
  end
end
