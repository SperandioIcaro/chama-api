defmodule ChamaApi.RoomsTest do
  use ChamaApi.DataCase

  alias ChamaApi.Rooms

  import ChamaApi.AccountsFixtures

  test "a sala geral existe uma única vez" do
    a = Rooms.ensure_general_room()
    b = Rooms.ensure_general_room()

    assert a.id == b.id
    assert a.kind == "general"
    assert a.code == Rooms.general_code()
  end

  test "sala geral é aberta: entra direto, sem aprovação" do
    user = user_fixture()
    assert {:ok, _room, %{status: "approved"}, :joined} = Rooms.join_room_by_code("geral", user)
  end

  test "create_room/2 cria sala privada e coloca o criador como host aprovado" do
    owner = user_fixture()

    assert {:ok, room} =
             Rooms.create_room(%{"name" => "Daily do Caos", "kind" => "general"}, owner)

    # `kind` enviado pelo cliente é ignorado
    assert room.kind == "private"
    assert Rooms.owner?(room, owner)
    assert %{role: "host", status: "approved"} = Rooms.get_active_participant(room.id, owner.id)
    assert {:ok, _room, _p, :joined} = Rooms.join_room_by_code(room.code, owner)
  end

  test "salas privadas de terceiros não aparecem na listagem (nem para quem só pediu para entrar)" do
    owner = user_fixture()
    other = user_fixture()
    {:ok, room} = Rooms.create_room(%{"name" => "Sala secreta"}, owner)

    {:ok, _, _, :requested} = Rooms.join_room_by_code(room.code, other)

    ids_owner = owner |> Rooms.list_rooms_for() |> Enum.map(& &1.id)
    ids_other = other |> Rooms.list_rooms_for() |> Enum.map(& &1.id)

    assert room.id in ids_owner
    refute room.id in ids_other
    # a geral aparece para todos, e vem primeiro
    assert hd(Rooms.list_rooms_for(other)).kind == "general"
  end

  test "entrar por código/link exige aprovação do admin" do
    owner = user_fixture()
    guest = user_fixture()
    {:ok, room} = Rooms.create_room(%{"name" => "Convite"}, owner)

    assert {:ok, _room, %{status: "pending"}, :requested} =
             Rooms.join_room_by_code(room.code, guest)

    assert {:ok, _room, %{status: "pending"}, :pending} =
             Rooms.join_room_by_code(room.code, guest)

    assert {:error, :not_participant} = Rooms.ensure_participant_active(room.id, guest.id)
    assert Rooms.access_status(room, guest) == "pending"

    assert [%{user_id: uid}] = Rooms.list_pending_requests(room)
    assert uid == guest.id

    assert {:ok, _} = Rooms.approve_request(room, guest.id)
    assert :ok = Rooms.ensure_participant_active(room.id, guest.id)
    assert Rooms.list_pending_requests(room) == []

    # quem já foi aprovado volta sem novo pedido
    assert {:ok, _} = Rooms.leave_room(room, guest)

    assert {:ok, _room, %{status: "approved"}, :joined} =
             Rooms.join_room_by_code(room.code, guest)
  end

  test "admin pode negar e a pessoa pode pedir de novo" do
    owner = user_fixture()
    guest = user_fixture()
    {:ok, room} = Rooms.create_room(%{"name" => "Fechada"}, owner)

    {:ok, _, _, :requested} = Rooms.join_room_by_code(room.code, guest)
    assert {:ok, _} = Rooms.deny_request(room, guest.id)
    assert Rooms.access_status(room, guest) == "denied"
    assert {:error, :not_participant} = Rooms.ensure_participant_active(room.id, guest.id)

    assert {:error, :request_not_found} = Rooms.approve_request(room, guest.id)

    assert {:ok, _, %{status: "pending"}, :requested} = Rooms.join_room_by_code(room.code, guest)
  end

  test "convite direto dispensa a aprovação" do
    owner = user_fixture()
    guest = user_fixture()
    {:ok, room} = Rooms.create_room(%{"name" => "Convidados"}, owner)

    assert {:ok, _} = Rooms.invite_user(room, guest.id)
    # convidado ainda não está dentro até aceitar (entrar)
    assert {:error, :not_participant} = Rooms.ensure_participant_active(room.id, guest.id)

    assert {:ok, _room, %{status: "approved"}, :joined} =
             Rooms.join_room_by_code(room.code, guest)

    assert {:error, :already_member} = Rooms.invite_user(room, guest.id)
  end

  test "recusar o convite remove o pré-acesso" do
    owner = user_fixture()
    guest = user_fixture()
    {:ok, room} = Rooms.create_room(%{"name" => "Recusa"}, owner)

    {:ok, _} = Rooms.invite_user(room, guest.id)
    assert Rooms.access_status(room, guest) == "invited"

    :ok = Rooms.revoke_invite(room, guest)
    assert Rooms.access_status(room, guest) == "none"
  end

  test "código inexistente e sala desativada" do
    owner = user_fixture()
    assert {:error, :room_not_found} = Rooms.join_room_by_code("nao-existe", owner)

    {:ok, room} = Rooms.create_room(%{"name" => "Vai fechar"}, owner)
    {:ok, _} = Rooms.update_room(room, %{"is_active" => false})
    assert {:error, :room_inactive} = Rooms.join_room_by_code(room.code, owner)
  end

  test "mensagens são salvas e listadas da mais antiga para a mais nova" do
    user = user_fixture(%{name: "Beltrano"})
    room = Rooms.ensure_general_room()

    assert {:ok, m1} = Rooms.create_message(room, user, "  primeira  ")
    assert {:ok, _m2} = Rooms.create_message(room, user, "segunda")
    assert m1.body == "primeira"
    assert m1.user_name == "Beltrano"

    assert [%{body: "primeira"}, %{body: "segunda"}] = Rooms.list_messages(room)
    assert [%{body: "segunda"}] = Rooms.list_messages(room, 1)

    assert {:error, _} = Rooms.create_message(room, user, "   ")
  end

  test "participant_counts/1 conta só quem está aprovado na sala" do
    owner = user_fixture()
    guest = user_fixture()
    {:ok, room} = Rooms.create_room(%{"name" => "Contagem"}, owner)

    {:ok, _, _, :requested} = Rooms.join_room_by_code(room.code, guest)
    assert Rooms.participant_counts([room.id])[room.id] == 1

    {:ok, _} = Rooms.approve_request(room, guest.id)
    assert Rooms.participant_counts([room.id])[room.id] == 2

    {:ok, _} = Rooms.leave_room(room, guest)
    assert Rooms.participant_counts([room.id])[room.id] == 1
    assert Rooms.participant_counts([]) == %{}
  end
end
