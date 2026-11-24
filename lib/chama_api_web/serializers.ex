defmodule ChamaApiWeb.Serializers do
  @moduledoc "Formato JSON único para usuários e salas (usado por controllers e channels)."

  alias ChamaApi.Accounts.User
  alias ChamaApi.Rooms.Room

  def user(%User{} = u) do
    %{
      id: u.id,
      name: u.name,
      email: u.email,
      avatar_url: u.avatar_url,
      github_login: u.github_login
    }
  end

  @doc "Versão pública (sem email) — para presença e convites."
  def public_user(%User{} = u), do: %{id: u.id, name: u.name, avatar_url: u.avatar_url}

  def room(%Room{} = r, opts \\ []) do
    %{
      id: r.id,
      name: r.name,
      code: r.code,
      kind: r.kind,
      is_active: r.is_active,
      created_by_id: r.created_by_id,
      inserted_at: r.inserted_at
    }
    |> maybe_put(:participants_count, opts[:participants_count])
    |> maybe_put(:is_owner, owner_flag(r, opts[:user]))
  end

  defp owner_flag(%Room{created_by_id: id}, %User{id: user_id}), do: id == user_id
  defp owner_flag(_room, _user), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
