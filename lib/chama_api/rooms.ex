defmodule ChamaApi.Rooms do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ChamaApi.Repo
  alias ChamaApi.Rooms.{Message, Participant, Room}

  @general_code "geral"
  @general_name "Sala Geral"
  @messages_default 50
  @messages_max 100

  def general_code, do: @general_code

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  # =========================
  # Salas
  # =========================

  @doc "A sala geral é criada sob demanda (e de forma segura contra corrida)."
  def ensure_general_room do
    case Repo.get_by(Room, code: @general_code) do
      %Room{} = room ->
        room

      nil ->
        Repo.insert(
          %Room{name: @general_name, code: @general_code, kind: "general"},
          on_conflict: :nothing,
          conflict_target: :code
        )

        Repo.get_by!(Room, code: @general_code)
    end
  end

  @doc """
  Salas que o usuário enxerga: a geral + as privadas em que ele está.
  Salas privadas de terceiros NUNCA aparecem aqui (o código é o convite).
  """
  def list_rooms_for(user) do
    ensure_general_room()

    member_room_ids =
      from p in Participant,
        where: p.user_id == ^user.id and p.status == "approved" and is_nil(p.left_at),
        select: p.room_id

    Repo.all(
      from r in Room,
        where: r.is_active == true and (r.kind == "general" or r.id in subquery(member_room_ids)),
        order_by: [asc: r.kind, desc: r.inserted_at]
    )
  end

  @doc "Contagem de participantes ativos em UMA query (evita N+1 na listagem)."
  def participant_counts([]), do: %{}

  def participant_counts(room_ids) do
    from(p in Participant,
      where: p.room_id in ^room_ids and p.status == "approved" and is_nil(p.left_at),
      group_by: p.room_id,
      select: {p.room_id, count(p.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  def get_room(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Room, uuid)
      :error -> nil
    end
  end

  def get_room_by_code(@general_code), do: ensure_general_room()
  def get_room_by_code(code) when is_binary(code), do: Repo.get_by(Room, code: code)
  def get_room_by_code(_), do: nil

  def get_room_by_code_active(code) do
    case get_room_by_code(code) do
      nil -> {:error, :room_not_found}
      %Room{is_active: true} = room -> {:ok, room}
      %Room{} -> {:error, :room_inactive}
    end
  end

  def owner?(%Room{created_by_id: id}, %{id: id}) when not is_nil(id), do: true
  def owner?(_room, _user), do: false

  def can_view?(%Room{kind: "general"}, _user), do: true
  def can_view?(%Room{} = room, user), do: get_active_participant(room.id, user.id) != nil

  @doc "Cria uma sala privada e já coloca o criador como `host` (na mesma transação)."
  def create_room(attrs, %{id: user_id}) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:room, Room.create_changeset(%Room{created_by_id: user_id}, attrs))
    |> Ecto.Multi.insert(:participant, fn %{room: room} ->
      Participant.create_changeset(%Participant{}, %{
        room_id: room.id,
        user_id: user_id,
        role: "host",
        joined_at: now()
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{room: room}} -> {:ok, room}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  def update_room(%Room{} = room, attrs) do
    room
    |> Room.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_room(%Room{} = room), do: Repo.delete(room)

  # =========================
  # Participantes
  # =========================

  def get_active_participant(room_id, user_id) do
    Repo.one(
      from p in Participant,
        where:
          p.room_id == ^room_id and p.user_id == ^user_id and p.status == "approved" and
            is_nil(p.left_at)
    )
  end

  def list_active_participants(room_id) do
    Repo.all(
      from p in Participant,
        join: u in assoc(p, :user),
        where: p.room_id == ^room_id and p.status == "approved" and is_nil(p.left_at),
        order_by: [asc: p.joined_at, asc: p.inserted_at],
        select: %{
          id: p.id,
          user_id: u.id,
          role: p.role,
          joined_at: p.joined_at,
          name: u.name,
          avatar_url: u.avatar_url
        }
    )
  end

  def ensure_participant_active(room_id, user_id) do
    case get_active_participant(room_id, user_id) do
      nil -> {:error, :not_participant}
      %Participant{} -> :ok
    end
  end

  @doc """
  Coloca o usuário na sala como membro aprovado (idempotente). Usado pela sala geral,
  pelo dono da sala e quando o admin aprova / o convite é aceito.
  """
  def join_room(%Room{} = room, user) do
    case Repo.get_by(Participant, room_id: room.id, user_id: user.id) do
      nil ->
        %Participant{}
        |> Participant.create_changeset(%{
          room_id: room.id,
          user_id: user.id,
          role: "member",
          status: "approved",
          joined_at: now()
        })
        |> Repo.insert()

      %Participant{status: "approved", left_at: nil} = participant ->
        {:ok, participant}

      %Participant{} = participant ->
        participant
        |> Ecto.Changeset.change(status: "approved", left_at: nil, joined_at: now())
        |> Repo.update()
    end
  end

  @doc """
  Entrar pelo código/link.

    * sala geral, dono, quem já é membro ou foi convidado direto → entra (`:joined`)
    * qualquer outra pessoa → fica `pending` até o admin liberar
      (`:requested` = pedido novo, avisar o admin; `:pending` = já estava esperando)
  """
  def join_room_by_code(code, user) do
    with {:ok, room} <- get_room_by_code_active(code),
         {:ok, participant, event} <- join_or_request(room, user) do
      {:ok, room, participant, event}
    end
  end

  defp join_or_request(%Room{kind: "general"} = room, user), do: joined(room, user)

  defp join_or_request(%Room{} = room, user) do
    if owner?(room, user) do
      joined(room, user)
    else
      case Repo.get_by(Participant, room_id: room.id, user_id: user.id) do
        nil -> insert_pending(room, user)
        %Participant{status: status} when status in ["approved", "invited"] -> joined(room, user)
        %Participant{status: "pending"} = participant -> {:ok, participant, :pending}
        %Participant{status: "denied"} = participant -> reopen_request(participant)
      end
    end
  end

  defp joined(room, user) do
    with {:ok, participant} <- join_room(room, user), do: {:ok, participant, :joined}
  end

  defp insert_pending(room, user) do
    %Participant{}
    |> Participant.create_changeset(%{
      room_id: room.id,
      user_id: user.id,
      role: "member",
      status: "pending"
    })
    |> Repo.insert()
    |> case do
      {:ok, participant} -> {:ok, participant, :requested}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp reopen_request(participant) do
    participant
    |> Ecto.Changeset.change(status: "pending")
    |> Repo.update()
    |> case do
      {:ok, participant} -> {:ok, participant, :requested}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Situação do usuário na sala: approved | pending | invited | denied | none."
  def access_status(%Room{kind: "general"}, _user), do: "approved"

  def access_status(%Room{} = room, user) do
    if owner?(room, user) do
      "approved"
    else
      case Repo.get_by(Participant, room_id: room.id, user_id: user.id) do
        nil -> "none"
        %Participant{status: status} -> status
      end
    end
  end

  @doc "Convite direto: a pessoa entra sem precisar de aprovação do admin."
  def invite_user(%Room{} = room, to_user_id) do
    case Repo.get_by(Participant, room_id: room.id, user_id: to_user_id) do
      nil ->
        %Participant{}
        |> Participant.create_changeset(%{
          room_id: room.id,
          user_id: to_user_id,
          role: "member",
          status: "invited"
        })
        |> Repo.insert()

      %Participant{status: "approved", left_at: nil} ->
        {:error, :already_member}

      %Participant{} = participant ->
        participant |> Ecto.Changeset.change(status: "invited") |> Repo.update()
    end
  end

  @doc "A pessoa recusou o convite: some o pré-acesso."
  def revoke_invite(%Room{} = room, user) do
    Repo.delete_all(
      from p in Participant,
        where: p.room_id == ^room.id and p.user_id == ^user.id and p.status == "invited"
    )

    :ok
  end

  def list_pending_requests(%Room{} = room) do
    Repo.all(
      from p in Participant,
        join: u in assoc(p, :user),
        where: p.room_id == ^room.id and p.status == "pending",
        order_by: [asc: p.inserted_at],
        select: %{
          user_id: u.id,
          name: u.name,
          avatar_url: u.avatar_url,
          requested_at: p.inserted_at
        }
    )
  end

  def approve_request(%Room{} = room, user_id),
    do: update_pending(room, user_id, status: "approved", left_at: nil, joined_at: now())

  def deny_request(%Room{} = room, user_id), do: update_pending(room, user_id, status: "denied")

  defp update_pending(room, user_id, changes) do
    case Repo.get_by(Participant, room_id: room.id, user_id: user_id, status: "pending") do
      nil -> {:error, :request_not_found}
      participant -> participant |> Ecto.Changeset.change(changes) |> Repo.update()
    end
  end

  def leave_room(%Room{} = room, user) do
    case get_active_participant(room.id, user.id) do
      nil ->
        {:error, :not_in_room}

      %Participant{} = participant ->
        participant
        |> Ecto.Changeset.change(left_at: now())
        |> Repo.update()
    end
  end

  # =========================
  # Mensagens (chat da sala / mural da sala geral)
  # =========================

  @doc "Últimas mensagens da sala, da mais antiga para a mais nova, já com nome/avatar."
  def list_messages(%Room{} = room, limit \\ @messages_default) do
    limit = limit |> max(1) |> min(@messages_max)

    from(m in Message,
      join: u in assoc(m, :user),
      where: m.room_id == ^room.id,
      order_by: [desc: m.inserted_at, desc: m.id],
      limit: ^limit,
      select: %{
        id: m.id,
        body: m.body,
        inserted_at: m.inserted_at,
        user_id: u.id,
        user_name: u.name,
        avatar_url: u.avatar_url
      }
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  def create_message(%Room{} = room, user, body) do
    %Message{room_id: room.id, user_id: user.id}
    |> Message.changeset(%{body: body})
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        {:ok,
         %{
           id: message.id,
           body: message.body,
           inserted_at: message.inserted_at,
           user_id: user.id,
           user_name: user.name,
           avatar_url: user.avatar_url
         }}

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
