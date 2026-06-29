defmodule DoneManager.Pushover do
  @moduledoc """
  Thin client for the [Pushover](https://pushover.net) messages API.

  Requires the shared application token in config:

      config :done_manager, DoneManager.Pushover, app_token: "..."

  Tests inject a stub transport via `config :done_manager, DoneManager.Pushover,
  plug: {Req.Test, DoneManager.Pushover}`.
  """

  require Logger

  @url "https://api.pushover.net/1/messages.json"

  @doc """
  Sends `message` to the device(s) identified by `user_key`.

  Options:
    * `:title` — optional notification title.
    * `:priority` — optional Pushover priority (e.g. `-1` for silent delivery).

  Returns `:ok`, or `{:error, reason}` on a transport failure, non-200 response,
  or a Pushover body with `status != 1`.
  """
  def send_message(user_key, message, opts \\ [])

  def send_message(user_key, _message, _opts) when user_key in [nil, ""],
    do: {:error, :no_user_key}

  def send_message(user_key, message, opts) do
    params =
      %{token: app_token(), user: user_key, message: message}
      |> maybe_put(:title, opts[:title])
      |> maybe_put(:priority, opts[:priority])

    case Req.post(req_options(form: params)) do
      {:ok, %Req.Response{status: 200, body: %{"status" => 1}}} ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Pushover send failed: status=#{status} body=#{inspect(body)}")
        {:error, {:pushover, status, body}}

      {:error, reason} ->
        Logger.error("Pushover request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp req_options(extra) do
    base = [url: @url]
    base = if plug = config()[:plug], do: Keyword.put(base, :plug, plug), else: base
    Keyword.merge(base, extra)
  end

  defp app_token, do: Keyword.fetch!(config(), :app_token)

  defp config, do: Application.get_env(:done_manager, __MODULE__, [])
end
