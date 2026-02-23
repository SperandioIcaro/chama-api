defmodule ChamaApi.Repo.Migrations.AddLeftAtToParticipants do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:participants, [:room_id, :user_id])
    create_if_not_exists index(:participants, [:room_id, :left_at])
  end
end
