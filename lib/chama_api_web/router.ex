defmodule ChamaApiWeb.Router do
  use ChamaApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug ChamaApi.Auth.Pipeline
  end

  scope "/api", ChamaApiWeb do
    # rotas públicas
    pipe_through :api

    post "/register", AuthController, :register
    post "/login", AuthController, :login

    # rotas protegidas
    scope "/" do
      pipe_through :auth

      get "/me", UserController, :me

      # Rooms
      get "/rooms", RoomController, :index
      post "/rooms", RoomController, :create
      get "/rooms/:id", RoomController, :show
      patch "/rooms/:id", RoomController, :update
      delete "/rooms/:id", RoomController, :delete
    end
  end
end
