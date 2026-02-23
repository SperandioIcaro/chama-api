defmodule ChamaApi.Repo.Migrations.CreateParticipants do
  use Ecto.Migration

  def change do
    create table(:participants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false, default: "member"
      add :left_at, :utc_datetime

      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:participants, [:room_id])
    create index(:participants, [:user_id])

    # Impede o mesmo usuário entrar 2x na mesma sala (enquanto não saiu)
    create unique_index(:participants, [:room_id, :user_id], name: :participants_room_user_unique)
  end
end
