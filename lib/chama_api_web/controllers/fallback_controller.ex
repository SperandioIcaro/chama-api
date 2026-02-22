defmodule ChamaApiWeb.FallbackController do
  use ChamaApiWeb, :controller

  # -------------------------
  # VALIDATION (422)
  # -------------------------
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: "validation_error",
      message: "Alguns campos estão inválidos. Corrija e tente novamente.",
      status: 422,
      fields: humanize_errors(changeset),
      how_to_fix: "Envie os campos obrigatórios no formato correto.",
      example:
        ~s(curl -X POST http://localhost:4000/api/register -H "content-type: application/json" -d '{"name":"Seu Nome","email":"voce@exemplo.com","password":"minimo8"}')
    })
  end

  # -------------------------
  # AUTH (401 / 400)
  # -------------------------
  def call(conn, {:error, :invalid_credentials}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{
      error: "invalid_credentials",
      message: "Email ou senha incorretos.",
      status: 401,
      how_to_fix: "Confira o email/senha e tente novamente.",
      example:
        ~s(curl -X POST http://localhost:4000/api/login -H "content-type: application/json" -d '{"email":"teste@teste.com","password":"12345678"}')
    })
  end

  def call(conn, {:error, :email_and_password_required}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "email_and_password_required",
      message: "Você precisa enviar email e password no corpo da requisição.",
      status: 400,
      how_to_fix: "Envie JSON com {\"email\":\"...\",\"password\":\"...\"}.",
      example:
        ~s(curl -X POST http://localhost:4000/api/login -H "content-type: application/json" -d '{"email":"teste@teste.com","password":"12345678"}')
    })
  end

  # -------------------------
  # NOT FOUND (404)
  # -------------------------
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{
      error: "not_found",
      message: "Recurso não encontrado.",
      status: 404
    })
  end

  # -------------------------
  # DEFAULT FALLBACK (400)
  # -------------------------
  def call(conn, {:error, reason}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "bad_request",
      message: "Não foi possível processar sua requisição.",
      status: 400,
      details: inspect(reason)
    })
  end

  # -------------------------
  # Helpers
  # -------------------------
  defp humanize_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      msg = interpolate_msg(msg, opts)
      pretty_msg(msg)
    end)
  end

  defp interpolate_msg(msg, opts) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp pretty_msg("can't be blank"), do: "é obrigatório"
  defp pretty_msg("should be at least " <> rest), do: "deve ter no mínimo " <> rest
  defp pretty_msg(other), do: other
end
