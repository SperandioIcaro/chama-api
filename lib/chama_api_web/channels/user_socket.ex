defmodule ChamaApiWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", ChamaApiWeb.RoomChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case fetch_user_from_token(token) do
      {:ok, user} ->
        {:ok, assign(socket, :current_user, user)}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(_socket), do: nil

  # -------------------------
  # Helpers
  # -------------------------
  defp fetch_user_from_token(token) do
    case ChamaApi.Auth.Guardian.resource_from_token(token) do
      {:ok, user, _claims} -> {:ok, user}
      _ -> try_decode_and_load(token)
    end
  end

  defp try_decode_and_load(token) do
    with {:ok, claims} <- ChamaApi.Auth.Guardian.decode_and_verify(token),
         {:ok, user} <- ChamaApi.Auth.Guardian.resource_from_claims(claims) do
      {:ok, user}
    else
      _ -> {:error, :invalid_token}
    end
  end
end
