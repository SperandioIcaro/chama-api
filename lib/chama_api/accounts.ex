alias ChamaApi.Accounts.User
alias ChamaApi.Repo

def register_user(attrs) do
  %User{}
  |> User.registration_changeset(attrs)
  |> Repo.insert()
end

def authenticate_user(email, password) do
  case Repo.get_by(User, email: email) do
    nil ->
      {:error, :invalid_credentials}

    user ->
      if Bcrypt.verify_pass(password, user.password_hash) do
        {:ok, user}
      else
        {:error, :invalid_credentials}
      end
  end
end
