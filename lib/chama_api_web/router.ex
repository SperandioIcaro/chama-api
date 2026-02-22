scope "/api", ChamaApiWeb do
  pipe_through :api

  post "/signup", AuthController, :signup
  post "/login", AuthController, :login
end
