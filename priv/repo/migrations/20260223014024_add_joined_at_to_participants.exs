defmodule ChamaApi.Repo.Migrations.AddJoinedAtToParticipants do
  use Ecto.Migration

  def change do
    alter table(:participants) do
      add :joined_at, :utc_datetime
    end

    create index(:participants, [:room_id, :joined_at])
  end
end
