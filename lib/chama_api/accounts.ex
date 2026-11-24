defmodule ChamaApi.Accounts do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ChamaApi.Accounts.User
  alias ChamaApi.Repo

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def get_user(id), do: Repo.get(User, id)

  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    email = User.normalize_email(email)

    user =
      Repo.one(
        from u in User,
          where: fragment("lower(?)", u.email) == ^email,
          limit: 1
      )

    case user do
      %User{password_hash: hash} when is_binary(hash) ->
        if Bcrypt.verify_pass(password, hash),
          do: {:ok, user},
          else: {:error, :invalid_credentials}

      _ ->
        # Conta inexistente ou criada só pelo GitHub: gasta o mesmo tempo para
        # não revelar (por timing) quais emails existem.
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def authenticate_user(_email, _password), do: {:error, :invalid_credentials}

  @doc """
  Cria ou atualiza a conta ligada a um perfil do GitHub.

  Não liga automaticamente a uma conta de email/senha já existente: se o email
  do GitHub já estiver em uso, a conta nova nasce sem email (evita tomada de
  conta por email).
  """
  def upsert_github_user(%{"id" => github_id, "login" => login} = profile)
      when is_integer(github_id) and is_binary(login) do
    avatar_url = profile["avatar_url"]

    case Repo.get_by(User, github_id: github_id) do
      %User{} = user ->
        user
        |> User.github_profile_changeset(%{github_login: login, avatar_url: avatar_url})
        |> Repo.update()

      nil ->
        %User{}
        |> User.github_changeset(%{
          github_id: github_id,
          github_login: login,
          avatar_url: avatar_url,
          name: present(profile["name"]) || login,
          email: free_email(profile["email"])
        })
        |> Repo.insert()
    end
  end

  def upsert_github_user(_profile), do: {:error, :invalid_github_profile}

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_), do: nil

  defp free_email(email) when is_binary(email) do
    email = User.normalize_email(email)

    if Repo.exists?(from u in User, where: fragment("lower(?)", u.email) == ^email),
      do: nil,
      else: email
  end

  defp free_email(_), do: nil
end
