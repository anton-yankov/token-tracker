defmodule TokenTracker.Quota do
  @moduledoc """
  Subscription quota snapshot for the local Claude Code and Codex accounts.

  Providers are queried on demand and cached for a short interval so dashboard
  refreshes never hammer the upstream usage endpoints (Anthropic's in
  particular rate limits aggressively). When a provider fails, the last good
  snapshot is served alongside the error so the dashboard can render stale
  bars instead of an empty card.
  """

  @cache_key {__MODULE__, :cache}
  @ttl_ms 60_000
  @forced_ttl_ms 10_000
  @fetch_timeout 20_000

  @providers [
    %{id: "claude", module: TokenTracker.Quota.Claude},
    %{id: "codex", module: TokenTracker.Quota.Codex}
  ]

  def report(opts \\ []) do
    force = Keyword.get(opts, :force, false)
    now = System.system_time(:millisecond)
    cache = read_cache()

    cache =
      if fresh?(cache, now, force) do
        cache
      else
        refresh(cache, now)
      end

    %{
      generated_at: iso(now),
      providers: Enum.map(@providers, &present(cache, &1.id))
    }
  end

  defp fresh?(%{fetched_at: fetched_at}, now, force) when is_integer(fetched_at) do
    ttl = if force, do: @forced_ttl_ms, else: @ttl_ms
    now - fetched_at < ttl
  end

  defp fresh?(_cache, _now, _force), do: false

  defp refresh(cache, now) do
    results =
      @providers
      |> Task.async_stream(fn provider -> {provider.id, provider.module.fetch()} end,
        timeout: @fetch_timeout,
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.zip(@providers)
      |> Map.new(fn
        {{:ok, {id, result}}, _provider} -> {id, result}
        {{:exit, _reason}, provider} -> {provider.id, {:error, "the usage check timed out"}}
      end)

    entries =
      Map.new(@providers, fn %{id: id} ->
        previous = cache[:entries][id] || %{data: nil, updated_at: nil, error: nil}

        entry =
          case results[id] do
            {:ok, data} -> %{data: data, updated_at: now, error: nil}
            {:error, reason} -> %{previous | error: reason}
          end

        {id, entry}
      end)

    cache = %{fetched_at: now, entries: entries}
    :persistent_term.put(@cache_key, cache)
    cache
  end

  defp read_cache do
    :persistent_term.get(@cache_key, %{fetched_at: nil, entries: %{}})
  end

  defp present(cache, id) do
    entry = cache[:entries][id] || %{data: nil, updated_at: nil, error: "unavailable"}

    base =
      entry.data ||
        %{id: id, label: String.capitalize(id), plan: nil, email: nil, windows: []}

    Map.merge(base, %{
      updated_at: entry.updated_at && iso(entry.updated_at),
      error: entry.error,
      stale: entry.error != nil and entry.data != nil
    })
  end

  defp iso(milliseconds) do
    milliseconds
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_iso8601()
  end
end
