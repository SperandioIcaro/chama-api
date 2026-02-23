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

    # Públicas
    post "/register", AuthController, :register
    post "/login", AuthController, :login
  end

  scope "/api", ChamaApiWeb do
    pipe_through [:api, :auth]

    # Protegidas
    get "/me", UserController, :me

    # Rooms
    get "/rooms", RoomController, :index
    post "/rooms", RoomController, :create

    get "/rooms/by-code/:code", RoomController, :by_code
    post "/rooms/by-code/:code/join", RoomController, :join
    post "/rooms/by-code/:code/leave", RoomController, :leave
    get "/rooms/by-code/:code/participants", RoomController, :participants_by_code

    get "/rooms/:id", RoomController, :show
    patch "/rooms/:id", RoomController, :update
    delete "/rooms/:id", RoomController, :delete
    get "/rooms/:id/participants", RoomController, :participants
  end
end
