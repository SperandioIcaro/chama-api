defmodule ChamaApi.Repo do
  use Ecto.Repo,
    otp_app: :chama_api,
    adapter: Ecto.Adapters.Postgres
end
