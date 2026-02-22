defmodule ChamaApi.Auth.Guardian do
  use Guardian, otp_app: :chama_api

  alias ChamaApi.Accounts

  # quando gera o token
  def subject_for_token(%{id: id}, _claims), do: {:ok, to_string(id)}
  def subject_for_token(_, _), do: {:error, :no_subject}

  # quando valida o token (AQUI é o pulo do gato)
  def resource_from_claims(%{"sub" => id}) do
    case Accounts.get_user(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_claims), do: {:error, :no_sub}
end
