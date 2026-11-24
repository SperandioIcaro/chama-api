defmodule ChamaApiWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", ChamaApiWeb.RoomChannel
  channel "lobby:*", ChamaApiWeb.LobbyChannel
  channel "user:*", ChamaApiWeb.UserChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case fetch_user_from_token(token) do
      {:ok, user} -> {:ok, assign(socket, :current_user, user)}
      {:error, _reason} -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  # Permite derrubar todas as conexões de um usuário: ChamaApiWeb.Endpoint.broadcast("user_socket:<id>", "disconnect", %{})
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"

  defp fetch_user_from_token(token) do
    with {:ok, claims} <- ChamaApi.Auth.Guardian.decode_and_verify(token),
         {:ok, user} <- ChamaApi.Auth.Guardian.resource_from_claims(claims) do
      {:ok, user}
    else
      _ -> {:error, :invalid_token}
    end
  end
end
