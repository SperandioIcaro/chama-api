defmodule ChamaApi.Auth.Guardian do
  use Guardian, otp_app: :chama_api

  def subject_for_token(%{id: id}, _claims), do: {:ok, to_string(id)}
  def subject_for_token(_, _), do: {:error, :no_subject}

  def resource_from_claims(%{"sub" => id}) do
    # Depois a gente busca no Repo; por enquanto basta devolver o id
    {:ok, %{id: id}}
  end

  def resource_from_claims(_), do: {:error, :no_resource}
end
