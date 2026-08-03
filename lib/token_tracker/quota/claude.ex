defmodule TokenTracker.Quota.Claude do
  @moduledoc false

  @usage_url "https://api.anthropic.com/api/oauth/usage"
  @keychain_service "Claude Code-credentials"
  @credentials_file "~/.claude/.credentials.json"
  @keychain_timeout 5_000

  def fetch do
    with {:ok, credentials} <- credentials() do
      request(credentials)
    end
  end

  defp credentials do
    case keychain_credentials() do
      {:ok, credentials} -> {:ok, credentials}
      {:error, _reason} -> file_credentials()
    end
  end

  defp keychain_credentials do
    task =
      Task.async(fn ->
        System.cmd("security", ["find-generic-password", "-s", @keychain_service, "-w"],
          stderr_to_stdout: true
        )
      end)

    case Task.yield(task, @keychain_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} -> parse_credentials(output)
      {:ok, {_output, _status}} -> {:error, "Claude credentials were not found in the Keychain"}
      _ -> {:error, "the Keychain did not respond"}
    end
  rescue
    ErlangError -> {:error, "the security command is unavailable"}
  end

  defp file_credentials do
    path = Path.expand(@credentials_file)

    with {:ok, body} <- File.read(path) do
      parse_credentials(body)
    else
      _ -> {:error, "Claude credentials were not found; sign in with Claude Code first"}
    end
  end

  defp parse_credentials(body) do
    with {:ok, decoded} <- Jason.decode(body),
         %{"accessToken" => token} = oauth when is_binary(token) <-
           Map.get(decoded, "claudeAiOauth") do
      check_expiry(%{
        token: token,
        plan: plan_label(oauth),
        expires_at: Map.get(oauth, "expiresAt")
      })
    else
      _ -> {:error, "Claude credentials could not be parsed"}
    end
  end

  defp check_expiry(%{expires_at: expires_at} = credentials) do
    if is_integer(expires_at) and expires_at < System.system_time(:millisecond) do
      {:error, "the Claude token has expired; open Claude Code to refresh it"}
    else
      {:ok, credentials}
    end
  end

  defp plan_label(oauth) do
    tier = Map.get(oauth, "rateLimitTier") || ""
    subscription = Map.get(oauth, "subscriptionType") || ""

    cond do
      String.contains?(tier, "20x") -> "Max 20x"
      String.contains?(tier, "5x") -> "Max 5x"
      subscription != "" -> String.capitalize(subscription)
      true -> nil
    end
  end

  defp request(credentials) do
    case Req.get(@usage_url,
           headers: [
             {"authorization", "Bearer #{credentials.token}"},
             {"anthropic-beta", "oauth-2025-04-20"},
             {"accept", "application/json"},
             {"user-agent", "claude-cli/2.1.0 (external, token-tracker)"}
           ],
           retry: false,
           connect_options: [timeout: 10_000],
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok,
         %{
           id: "claude",
           label: "Claude",
           plan: credentials.plan,
           email: nil,
           windows: windows(body)
         }}

      {:ok, %Req.Response{status: 401}} ->
        {:error, "the Claude token was rejected; open Claude Code to refresh it"}

      {:ok, %Req.Response{status: 429}} ->
        {:error, "Anthropic is rate limiting usage checks; retrying soon"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "the Claude usage endpoint returned HTTP #{status}"}

      {:error, error} ->
        {:error, "the Claude usage request failed: #{Exception.message(error)}"}
    end
  end

  # The modern response carries a `limits` array (session / weekly_all /
  # weekly_scoped); the flat five_hour / seven_day fields remain as a fallback.
  defp windows(%{"limits" => limits} = body) when is_list(limits) and limits != [] do
    limits
    |> Enum.map(&limit_window/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> fallback_windows(body)
      windows -> windows
    end
  end

  defp windows(body), do: fallback_windows(body)

  defp limit_window(%{"kind" => kind, "percent" => percent, "resets_at" => resets_at} = limit)
       when is_number(percent) and is_binary(resets_at) do
    case kind do
      "session" ->
        window("session", "5-hour limit", percent, resets_at, 300, false)

      "weekly_all" ->
        window("weekly", "7-day limit", percent, resets_at, 10_080, true)

      "weekly_scoped" ->
        name = get_in(limit, ["scope", "model", "display_name"]) || "model"

        window(
          "weekly_#{String.downcase(name)}",
          "7-day #{name}",
          percent,
          resets_at,
          10_080,
          true
        )

      _ ->
        nil
    end
  end

  defp limit_window(_limit), do: nil

  defp fallback_windows(body) do
    [
      {"session", "5-hour limit", "five_hour", 300, false},
      {"weekly", "7-day limit", "seven_day", 10_080, true},
      {"weekly_opus", "7-day Opus", "seven_day_opus", 10_080, true},
      {"weekly_sonnet", "7-day Sonnet", "seven_day_sonnet", 10_080, true}
    ]
    |> Enum.map(fn {id, label, key, minutes, weekly} ->
      case Map.get(body, key) do
        %{"utilization" => percent, "resets_at" => resets_at}
        when is_number(percent) and is_binary(resets_at) ->
          window(id, label, percent, resets_at, minutes, weekly)

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp window(id, label, percent, resets_at, minutes, weekly) do
    %{
      id: id,
      label: label,
      used_percent: percent * 1.0,
      resets_at: resets_at,
      window_minutes: minutes,
      weekly: weekly
    }
  end
end
