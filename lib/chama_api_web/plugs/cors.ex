defmodule ChamaApiWeb.Plugs.Cors do
  @moduledoc """
  CORS com origens lidas em runtime (`CORS_ORIGINS`, separadas por vírgula).

  O CORSPlug direto no endpoint fixa as origens em tempo de compilação, o que
  não funciona com releases configuradas por variável de ambiente.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    opts =
      CORSPlug.init(
        origin: Application.get_env(:chama_api, :cors_origins, ["http://localhost:5173"]),
        methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        headers: ["Authorization", "Content-Type", "Accept"],
        expose: ["Authorization"],
        max_age: 86_400
      )

    CORSPlug.call(conn, opts)
  end
end
