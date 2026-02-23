alias ChamaApi.Repo
alias ChamaApi.Accounts
alias ChamaApi.Accounts.User

email = System.get_env("SEED_ADMIN_EMAIL") || "admin@chama.local"
password = System.get_env("SEED_ADMIN_PASSWORD") || "Admin123!@#"
name = System.get_env("SEED_ADMIN_NAME") || "Chama Admin"

attrs = %{
  email: email,
  password: password,
  name: name,
  role: "admin"
}

user =
  Repo.get_by(User, email: email)

case user do
  nil ->
    IO.puts("👤 Criando admin seed: #{email}")

    case Accounts.register_user(attrs) do
      {:ok, _u} -> IO.puts("✅ Admin criado com sucesso.")
      {:error, changeset} -> IO.inspect(changeset.errors, label: "❌ Erros")
    end

  %User{} = u ->
    IO.puts("♻️ Admin já existe, garantindo senha/role...")

    # Ajuste conforme suas funções:
    u
    |> User.admin_seed_changeset(%{name: name, role: "admin"})
    |> Repo.update!()

    # Se sua atualização de senha for separada, use a função correta.
    # Exemplo genérico:
    case Accounts.update_user_password(u, %{password: password}) do
      {:ok, _} -> IO.puts("✅ Senha do admin atualizada.")
      {:error, changeset} -> IO.inspect(changeset.errors, label: "❌ Erros senha")
    end
end
