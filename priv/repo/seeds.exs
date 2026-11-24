# Rode com: mix run priv/repo/seeds.exs   (ou `mix ecto.setup`)
alias ChamaApi.{Accounts, Repo, Rooms}
alias ChamaApi.Accounts.User

# A sala geral é criada sob demanda, mas já deixamos pronta.
Rooms.ensure_general_room()
IO.puts("🏛️  Sala geral pronta (código: #{Rooms.general_code()})")

email = System.get_env("SEED_ADMIN_EMAIL") || "admin@chama.local"
password = System.get_env("SEED_ADMIN_PASSWORD") || "Admin123!@#"
name = System.get_env("SEED_ADMIN_NAME") || "Chama Admin"

case Repo.get_by(User, email: email) do
  nil ->
    IO.puts("👤 Criando usuário de desenvolvimento: #{email}")

    case Accounts.register_user(%{email: email, password: password, name: name}) do
      {:ok, _user} -> IO.puts("✅ Usuário criado.")
      {:error, changeset} -> IO.inspect(changeset.errors, label: "❌ Erros")
    end

  %User{} ->
    IO.puts("♻️  #{email} já existe, nada a fazer.")
end
