defmodule ChamaApiWeb.UserChannel do
  @moduledoc """
  Canal pessoal (`user:<meu_id>`): é por aqui que chegam os convites para salas
  privadas, só para o destinatário e em qualquer tela do app.
  """

  use ChamaApiWeb, :channel

  @impl true
  def join("user:" <> id, _payload, socket) do
    if socket.assigns.current_user.id == id do
      {:ok, socket}
    else
      {:error, %{reason: "forbidden"}}
    end
  end
end
