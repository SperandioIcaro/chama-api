defmodule ChamaApi.Auth.Pipeline do
  use Guardian.Plug.Pipeline,
    otp_app: :chama_api,
    module: ChamaApi.Auth.Guardian,
    error_handler: ChamaApi.Auth.ErrorHandler

  # Lê "Authorization: Bearer <token>"
  plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource
end
