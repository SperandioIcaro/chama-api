defmodule ChamaApiWeb.AuthController do
  use ChamaApiWeb, :controller

  action_fallback ChamaApiWeb.FallbackController

  alias ChamaApi.Accounts
  alias ChamaApi.Auth.Guardian

  # POST /api/register
  def register(conn, %{"user" => user_params}) do
    case ChamaApi.Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, token, _claims} = ChamaApi.Auth.Guardian.encode_and_sign(user)

        conn
        |> put_status(:created)
        |> json(%{
          token: token,
          user: %{id: user.id, name: user.name, email: user.email}
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: "validation_error", errors: errors})
    end
  end

  # POST /api/login
  def login(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- Accounts.authenticate_user(email, password),
         {:ok, token, _claims} <- Guardian.encode_and_sign(user) do
      json(conn, %{
        token: token,
        user: %{id: user.id, email: user.email, name: Map.get(user, :name)}
      })
    end
  end

  # Login sem email/senha no body
  def login(_conn, _params) do
    {:error, :email_and_password_required}
  end
end
