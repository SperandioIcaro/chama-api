defmodule ChamaApi.Auth.ErrorHandler do
  import Plug.Conn
  import Phoenix.Controller

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, reason}, _opts) do
    {status, payload} = build_payload(type, reason, conn)

    conn
    |> put_status(status)
    |> json(payload)
    |> halt()
  end

  defp build_payload(:unauthenticated, _reason, conn) do
    {:unauthorized,
     %{
       error: "auth_required",
       message: "Você precisa estar logado para acessar este recurso.",
       how_to_fix: "Envie o header Authorization: Bearer <seu_token>.",
       example: ~s(curl -H "authorization: Bearer SEU_TOKEN" #{base_url(conn)}/api/me),
       status: 401
     }}
  end

  defp build_payload(:invalid_token, _reason, _conn) do
    {:unauthorized,
     %{
       error: "invalid_token",
       message: "Seu token é inválido, expirou ou foi digitado errado.",
       how_to_fix: "Faça login novamente para obter um token novo.",
       endpoint: "/api/login",
       status: 401
     }}
  end

  defp build_payload(:unauthorized, reason, _conn) do
    {:unauthorized,
     %{
       error: "unauthorized",
       message: "Você não tem autorização para acessar este recurso.",
       details: format_reason(reason),
       status: 401
     }}
  end

  defp build_payload(:forbidden, reason, _conn) do
    {:forbidden,
     %{
       error: "forbidden",
       message: "Você está logado, mas não tem permissão para fazer isso.",
       details: format_reason(reason),
       status: 403
     }}
  end

  defp build_payload(other, reason, _conn) do
    {:unauthorized,
     %{
       error: Atom.to_string(other),
       message: "Falha de autenticação.",
       details: format_reason(reason),
       status: 401
     }}
  end

  defp format_reason(nil), do: nil
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)

  defp base_url(conn) do
    scheme = (conn.scheme || :http) |> Atom.to_string()
    host = conn.host || "localhost"
    port = conn.port

    if port in [80, 443] do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end
end
