defmodule ChamaApi.Auth.Token do
  use Joken.Config

  @impl true
  def token_config do
    default_claims()
  end

  def generate(user_id) do
    secret = Application.fetch_env!(:chama_api, :jwt_secret)
    signer = Joken.Signer.create("HS256", secret)

    generate_and_sign(%{"user_id" => user_id}, signer)
  end
end
