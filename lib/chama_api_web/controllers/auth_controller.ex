defmodule ChamaApiWeb.AuthController do
  use ChamaApiWeb, :controller

  action_fallback ChamaApiWeb.FallbackController

  alias ChamaApi.Accounts
  alias ChamaApi.Auth.Guardian

  # POST /api/register
  def register(conn, params) do
    with {:ok, user} <- Accounts.register_user(params) do
      conn
      |> put_status(:created)
      |> json(%{
        message: "user_created",
        user: %{id: user.id, email: user.email, name: Map.get(user, :name)}
      })
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
