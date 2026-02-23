defmodule ChamaApiWeb.Presence do
  use Phoenix.Presence,
    otp_app: :chama_api,
    pubsub_server: ChamaApi.PubSub
end
