defmodule ChamaApi.AccountsFixtures do
  @moduledoc """
  Helpers de teste para `ChamaApi.Accounts`.
  """

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"

  def valid_user_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Fulana de Tal",
      email: unique_user_email(),
      password: "senha1234"
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attrs()
      |> ChamaApi.Accounts.register_user()

    user
  end
end
