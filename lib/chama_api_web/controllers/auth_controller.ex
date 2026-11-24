defmodule ChamaApiWeb.AuthController do
  use ChamaApiWeb, :controller

  action_fallback ChamaApiWeb.FallbackController

  alias ChamaApi.{Accounts, GitHub}
  alias ChamaApi.Auth.Guardian
  alias ChamaApiWeb.Serializers

  # POST /api/register
  def register(conn, %{"user" => user_params}) when is_map(user_params) do
    with {:ok, user} <- Accounts.register_user(user_params),
         {:ok, token, _claims} <- Guardian.encode_and_sign(user) do
      conn
      |> put_status(:created)
      |> json(%{token: token, user: Serializers.user(user)})
    end
  end

  def register(_conn, _params), do: {:error, :user_payload_required}

  # POST /api/login
  def login(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- Accounts.authenticate_user(email, password),
         {:ok, token, _claims} <- Guardian.encode_and_sign(user) do
      json(conn, %{token: token, user: Serializers.user(user)})
    end
  end

  def login(_conn, _params), do: {:error, :email_and_password_required}

  # POST /api/auth/github  { code, redirect_uri? }
  # Mesmo endpoint para web e mobile: o cliente faz o redirecionamento do
  # GitHub, pega o `code` e manda para cá.
  def github(conn, %{"code" => code} = params) when is_binary(code) and code != "" do
    with {:ok, profile} <- GitHub.fetch_profile(code, params["redirect_uri"]),
         {:ok, user} <- Accounts.upsert_github_user(profile),
         {:ok, token, _claims} <- Guardian.encode_and_sign(user) do
      json(conn, %{token: token, user: Serializers.user(user)})
    end
  end

  def github(_conn, _params), do: {:error, :github_code_required}
end
