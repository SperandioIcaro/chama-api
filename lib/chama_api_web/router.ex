defmodule ChamaApiWeb.Router do
  use ChamaApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug ChamaApi.Auth.Pipeline
  end

  scope "/api", ChamaApiWeb do
    pipe_through :api

    post "/register", AuthController, :register
    post "/login", AuthController, :login
  end

  scope "/api", ChamaApiWeb do
    pipe_through [:api, :auth]

    get "/me", UserController, :me
  end
end
