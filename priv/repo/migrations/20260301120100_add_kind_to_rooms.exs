defmodule ChamaApi.Repo.Migrations.AddKindToRooms do
  use Ecto.Migration

  def change do
    alter table(:rooms) do
      # "general" = sala geral (mural aberto, estilo Heat) | "private" = sala por convite
      add :kind, :string, null: false, default: "private"
    end

    create index(:rooms, [:kind, :is_active])
  end
end
