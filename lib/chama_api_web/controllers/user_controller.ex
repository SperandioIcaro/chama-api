defmodule ChamaApiWeb.UserController do
  use ChamaApiWeb, :controller

  alias ChamaApiWeb.Serializers

  def me(conn, _params) do
    case Guardian.Plug.current_resource(conn) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthenticated"})

      user ->
        json(conn, %{user: Serializers.user(user)})
    end
  end
end
