defmodule ChamaApiWeb.CompactLogger do
  @moduledoc """
  Terminal enxuto em desenvolvimento: uma linha por requisição HTTP e aviso só quando
  uma entrada em canal é recusada. Ligado por `config :chama_api, compact_log: true`
  (veja config/dev.exs); fora do dev continua o log padrão do Phoenix.
  """

  require Logger

  def install do
    if Application.get_env(:chama_api, :compact_log, false) do
      :telemetry.attach_many(
        "chama-compact-log",
        [[:phoenix, :endpoint, :stop], [:phoenix, :channel_joined]],
        &__MODULE__.handle_event/4,
        nil
      )
    end

    :ok
  end

  def handle_event([:phoenix, :endpoint, :stop], %{duration: duration}, %{conn: conn}, _config) do
    # preflight de CORS é só ruído
    if conn.method != "OPTIONS" do
      Logger.info([
        String.pad_trailing(conn.method, 6),
        " ",
        conn.request_path,
        "  ",
        paint(conn.status, status_color(conn.status)),
        " ",
        paint(format_duration(duration), :faint)
      ])
    end

    :ok
  end

  def handle_event([:phoenix, :channel_joined], _measurements, %{result: :error, socket: socket}, _config) do
    Logger.warning("canal recusado: #{socket.topic}")
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  defp format_duration(native) do
    us = System.convert_time_unit(native, :native, :microsecond)
    if us < 1000, do: "#{us}µs", else: "#{div(us, 1000)}ms"
  end

  defp status_color(status) when is_integer(status) and status >= 500, do: :red
  defp status_color(status) when is_integer(status) and status >= 400, do: :yellow
  defp status_color(status) when is_integer(status) and status >= 300, do: :cyan
  defp status_color(_status), do: :green

  defp paint(text, color) do
    if Application.get_env(:chama_api, :compact_log_colors, false) do
      [color, to_string(text)] |> IO.ANSI.format(true) |> IO.iodata_to_binary()
    else
      to_string(text)
    end
  end
end
