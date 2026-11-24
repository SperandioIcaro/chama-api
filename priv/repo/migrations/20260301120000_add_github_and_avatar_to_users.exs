defmodule ChamaApi.Repo.Migrations.AddGithubAndAvatarToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :github_id, :bigint
      add :github_login, :string
      add :avatar_url, :string
    end

    # Um mesmo perfil do GitHub só pode estar ligado a uma conta do Chama.
    create unique_index(:users, [:github_id])
  end
end
