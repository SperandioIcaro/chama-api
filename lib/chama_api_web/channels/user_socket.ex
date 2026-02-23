defmodule ChamaApiWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", ChamaApiWeb.RoomChannel

  # WS params: token=JWT
  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case ChamaApi.Auth.Guardian.resource_from_token(token) do
      {:ok, user, _claims} ->
        {:ok, assign(socket, :current_user, user)}

      _ ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end
