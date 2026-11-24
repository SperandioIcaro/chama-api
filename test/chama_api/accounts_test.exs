defmodule ChamaApi.AccountsTest do
  use ChamaApi.DataCase

  alias ChamaApi.Accounts
  alias ChamaApi.Accounts.User

  import ChamaApi.AccountsFixtures

  describe "register_user/1" do
    test "cria usuário com senha criptografada e email normalizado" do
      assert {:ok, %User{} = user} =
               Accounts.register_user(%{
                 name: "  Maria   Silva ",
                 email: "  Maria@Example.COM ",
                 password: "senha1234"
               })

      assert user.name == "Maria Silva"
      assert user.email == "maria@example.com"
      assert user.password_hash != "senha1234"
      assert is_nil(user.github_id)
    end

    test "rejeita senha fraca" do
      assert {:error, cs} = Accounts.register_user(valid_user_attrs(%{password: "curta1"}))
      assert %{password: [_ | _]} = errors_on(cs)

      assert {:error, cs} = Accounts.register_user(valid_user_attrs(%{password: "somenteletras"}))
      assert "precisa ter ao menos um número" in errors_on(cs).password

      assert {:error, cs} = Accounts.register_user(valid_user_attrs(%{password: "12345678"}))
      assert "precisa ter ao menos uma letra" in errors_on(cs).password
    end

    test "rejeita email inválido e duplicado (ignorando maiúsculas)" do
      assert {:error, cs} = Accounts.register_user(valid_user_attrs(%{email: "isso-nao-e-email"}))
      assert %{email: [_ | _]} = errors_on(cs)

      user = user_fixture(%{email: "dup@example.com"})
      assert {:error, cs} = Accounts.register_user(valid_user_attrs(%{email: "DUP@example.com"}))
      assert "já está em uso" in errors_on(cs).email
      assert user.email == "dup@example.com"
    end
  end

  describe "authenticate_user/2" do
    test "aceita credenciais corretas (email sem diferenciar maiúsculas)" do
      user = user_fixture(%{email: "login@example.com", password: "senha1234"})

      assert {:ok, found} = Accounts.authenticate_user("LOGIN@example.com", "senha1234")
      assert found.id == user.id
    end

    test "recusa senha errada, usuário inexistente e conta só-GitHub" do
      user_fixture(%{email: "login@example.com", password: "senha1234"})

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("login@example.com", "errada123")

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("ninguem@example.com", "senha1234")

      {:ok, _gh} =
        Accounts.upsert_github_user(%{
          "id" => 99,
          "login" => "octo",
          "email" => "octo@example.com"
        })

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("octo@example.com", "qualquer123")
    end
  end

  describe "upsert_github_user/1" do
    test "cria na primeira vez e reaproveita nas seguintes" do
      profile = %{
        "id" => 1234,
        "login" => "octocat",
        "name" => "The Octocat",
        "avatar_url" => "https://a/1.png"
      }

      assert {:ok, user} = Accounts.upsert_github_user(profile)
      assert user.name == "The Octocat"
      assert user.github_login == "octocat"

      assert {:ok, again} =
               Accounts.upsert_github_user(%{profile | "avatar_url" => "https://a/2.png"})

      assert again.id == user.id
      assert again.avatar_url == "https://a/2.png"
    end

    test "usa o login quando o GitHub não informa nome" do
      assert {:ok, user} =
               Accounts.upsert_github_user(%{"id" => 7, "login" => "semnome", "name" => nil})

      assert user.name == "semnome"
    end

    test "não toma conta de email já cadastrado com senha" do
      existing = user_fixture(%{email: "dono@example.com"})

      assert {:ok, gh_user} =
               Accounts.upsert_github_user(%{
                 "id" => 5,
                 "login" => "intruso",
                 "email" => "dono@example.com"
               })

      assert gh_user.id != existing.id
      assert is_nil(gh_user.email)
    end
  end
end
