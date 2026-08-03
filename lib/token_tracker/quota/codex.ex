defmodule TokenTracker.Quota.Codex do
  @moduledoc false

  @usage_url "https://chatgpt.com/backend-api/wham/usage"
  @auth_file "~/.codex/auth.json"
  @weekly_threshold_seconds 6 * 86_400

  def fetch do
    with {:ok, credentials} <- credentials() do
      request(credentials)
    end
  end

  defp credentials do
    path = Path.expand(@auth_file)

    with {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body),
         %{"access_token" => token, "account_id" => account_id}
         when is_binary(token) and is_binary(account_id) <- Map.get(decoded, "tokens") do
      {:ok, %{token: token, account_id: account_id}}
    else
      _ -> {:error, "Codex credentials were not found; sign in with the Codex CLI first"}
    end
  end

  defp request(credentials) do
    case Req.get(@usage_url,
           headers: [
             {"authorization", "Bearer #{credentials.token}"},
             {"chatgpt-account-id", credentials.account_id},
             {"accept", "application/json"},
             {"user-agent", "token-tracker-quota"}
           ],
           retry: false,
           connect_options: [timeout: 10_000],
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok,
         %{
           id: "codex",
           label: "Codex",
           plan: plan_label(body),
           windows: windows(body)
         }}

      {:ok, %Req.Response{status: 401}} ->
        {:error, "the Codex token was rejected; run the Codex CLI to refresh it"}

      {:ok, %Req.Response{status: 429}} ->
        {:error, {:rate_limited, 0, "OpenAI is rate limiting usage checks; backing off"}}

      {:ok, %Req.Response{status: status}} ->
        {:error, "the Codex usage endpoint returned HTTP #{status}"}

      {:error, error} ->
        {:error, "the Codex usage request failed: #{Exception.message(error)}"}
    end
  end

  defp plan_label(body) do
    case Map.get(body, "plan_type") do
      plan when is_binary(plan) and plan != "" -> String.capitalize(plan)
      _ -> nil
    end
  end

  defp windows(body) do
    primary = rate_limit_windows(Map.get(body, "rate_limit"), "", "")

    code_review =
      rate_limit_windows(Map.get(body, "code_review_rate_limit"), "code_review_", "Code review ")

    additional =
      case Map.get(body, "additional_rate_limits") do
        limits when is_list(limits) -> Enum.flat_map(limits, &additional_windows/1)
        _ -> []
      end

    primary ++ code_review ++ additional
  end

  defp additional_windows(%{"rate_limit" => rate_limit} = limit) when is_map(rate_limit) do
    name = Map.get(limit, "limit_name") || Map.get(limit, "metered_feature") || "Additional"
    rate_limit_windows(rate_limit, "#{slug(name)}_", "#{name} ")
  end

  defp additional_windows(_limit), do: []

  defp rate_limit_windows(rate_limit, id_prefix, label_prefix) when is_map(rate_limit) do
    [
      {"primary", Map.get(rate_limit, "primary_window")},
      {"secondary", Map.get(rate_limit, "secondary_window")}
    ]
    |> Enum.map(fn {kind, window} -> window(window, kind, id_prefix, label_prefix) end)
    |> Enum.reject(&is_nil/1)
  end

  defp rate_limit_windows(_rate_limit, _id_prefix, _label_prefix), do: []

  defp window(
         %{
           "used_percent" => used_percent,
           "limit_window_seconds" => window_seconds,
           "reset_at" => reset_at
         },
         kind,
         id_prefix,
         label_prefix
       )
       when is_number(used_percent) and is_integer(window_seconds) and is_integer(reset_at) do
    weekly = window_seconds >= @weekly_threshold_seconds

    %{
      id: "#{id_prefix}#{kind}",
      label: "#{label_prefix}#{window_label(window_seconds)}",
      used_percent: used_percent * 1.0,
      resets_at: reset_at |> DateTime.from_unix!() |> DateTime.to_iso8601(),
      window_minutes: div(window_seconds, 60),
      weekly: weekly
    }
  end

  defp window(_window, _kind, _id_prefix, _label_prefix), do: nil

  defp window_label(seconds) do
    cond do
      seconds >= @weekly_threshold_seconds -> "Weekly limit"
      rem(seconds, 3600) == 0 -> "#{div(seconds, 3600)}-hour limit"
      true -> "#{div(seconds, 60)}-minute limit"
    end
  end

  defp slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end
end
