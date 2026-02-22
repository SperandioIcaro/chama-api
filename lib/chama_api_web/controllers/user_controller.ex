defmodule ChamaApiWeb.UserController do
  use ChamaApiWeb, :controller

  def me(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    case user do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthenticated"})

      user ->
        json(conn, %{
          user: %{
            id: user.id,
            email: user.email,
            name: Map.get(user, :name)
          }
        })
    end
  end
end
