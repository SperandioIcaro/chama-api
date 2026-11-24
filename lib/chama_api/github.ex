defmodule ChamaApi.GitHub do
  @moduledoc """
  Troca o `code` do OAuth do GitHub pelo perfil do usuário.

  Funciona igual para web e mobile: quem muda é só o `redirect_uri` que o
  cliente usou ao abrir a tela de autorização do GitHub.
  """

  @token_url "https://github.com/login/oauth/access_token"
  @user_url "https://api.github.com/user"
  @emails_url "https://api.github.com/user/emails"
  @timeout 8_000

  def fetch_profile(code, redirect_uri \\ nil) when is_binary(code) do
    with {:ok, client_id, client_secret} <- credentials(),
         {:ok, access_token} <- exchange_code(client_id, client_secret, code, redirect_uri),
         {:ok, profile} <- get_json(@user_url, access_token) do
      {:ok, Map.put(profile, "email", primary_verified_email(access_token))}
    end
  end

  defp credentials do
    cfg = Application.get_env(:chama_api, :github, [])

    case {cfg[:client_id], cfg[:client_secret]} do
      {id, secret} when is_binary(id) and id != "" and is_binary(secret) and secret != "" ->
        {:ok, id, secret}

      _ ->
        {:error, :github_not_configured}
    end
  end

  defp exchange_code(client_id, client_secret, code, redirect_uri) do
    form =
      [client_id: client_id, client_secret: client_secret, code: code] ++
        if(is_binary(redirect_uri) and redirect_uri != "", do: [redirect_uri: redirect_uri], else: [])

    result =
      Req.post(@token_url,
        form: form,
        headers: [accept: "application/json"],
        receive_timeout: @timeout,
        retry: false
      )

    case result do
      {:ok, %{status: 200, body: %{"access_token" => token}}} when is_binary(token) ->
        {:ok, token}

      {:ok, %{body: %{"error" => error}}} ->
        {:error, {:github_oauth, error}}

      {:ok, %{status: status}} ->
        {:error, {:github_http, status}}

      {:error, reason} ->
        {:error, {:github_unreachable, reason}}
    end
  end

  defp get_json(url, access_token) do
    result =
      Req.get(url,
        auth: {:bearer, access_token},
        headers: [accept: "application/vnd.github+json", user_agent: "chama-api"],
        receive_timeout: @timeout,
        retry: false
      )

    case result do
      {:ok, %{status: 200, body: body}} when is_map(body) or is_list(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:github_http, status}}
      {:error, reason} -> {:error, {:github_unreachable, reason}}
    end
  end

  # Precisa do escopo `user:email`. Se faltar ou falhar, o login segue sem email.
  defp primary_verified_email(access_token) do
    case get_json(@emails_url, access_token) do
      {:ok, emails} when is_list(emails) ->
        Enum.find_value(emails, fn
          %{"primary" => true, "verified" => true, "email" => email} -> email
          _ -> nil
        end)

      _ ->
        nil
    end
  end
end
