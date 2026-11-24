defmodule ChamaApi.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :name, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true

    # Preenchidos quando a conta nasce (ou é ligada) pelo login com GitHub.
    field :github_id, :integer
    field :github_login, :string
    field :avatar_url, :string

    timestamps(type: :utc_datetime)
  end

  @doc "Cadastro por email + senha."
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :password])
    |> update_change(:name, &normalize_spaces/1)
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:name, :email, :password])
    |> validate_length(:name, min: 2, max: 60)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "formato inválido")
    |> validate_length(:email, max: 160)
    |> validate_password()
    |> unique_constraint(:email, message: "já está em uso")
    |> put_password_hash()
  end

  @doc "Conta criada pelo primeiro login com GitHub (sem senha)."
  def github_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :github_id, :github_login, :avatar_url])
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:name, :github_id, :github_login])
    |> unique_constraint(:github_id)
    |> unique_constraint(:email, message: "já está em uso")
  end

  @doc "Atualiza login/avatar do GitHub em logins seguintes."
  def github_profile_changeset(user, attrs) do
    cast(user, attrs, [:github_login, :avatar_url])
  end

  def normalize_email(email) when is_binary(email), do: email |> String.trim() |> String.downcase()

  defp normalize_spaces(value) when is_binary(value) do
    value |> String.split() |> Enum.join(" ")
  end

  defp validate_password(changeset) do
    changeset
    # bcrypt só considera os 72 primeiros bytes
    |> validate_length(:password, min: 8, max: 72, count: :bytes)
    |> validate_format(:password, ~r/[A-Za-z]/, message: "precisa ter ao menos uma letra")
    |> validate_format(:password, ~r/[0-9]/, message: "precisa ter ao menos um número")
  end

  # Só gasta CPU com bcrypt quando o resto do cadastro é válido.
  defp put_password_hash(%Ecto.Changeset{valid?: true} = changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
    end
  end

  defp put_password_hash(changeset), do: changeset
end
