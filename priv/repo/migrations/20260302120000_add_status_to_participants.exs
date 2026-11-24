defmodule ChamaApi.Repo.Migrations.AddStatusToParticipants do
  use Ecto.Migration

  def change do
    alter table(:participants) do
      # approved = dentro da sala | pending = pediu para entrar (aguarda o admin)
      # invited = convidado direto por alguém da sala | denied = admin negou
      # (quem já estava nas salas continua "approved")
      add :status, :string, null: false, default: "approved"
    end

    create index(:participants, [:room_id, :status])
  end
end
