defmodule TokenTracker.Quota do
  @moduledoc """
  Subscription quota snapshot for the local Claude Code and Codex accounts.

  Providers are queried on demand with per-provider cadences: Anthropic's
  OAuth usage endpoint rate limits aggressively, so Claude refreshes on a
  slower clock than Codex and honours Retry-After with a backoff when a 429
  arrives anyway. When a provider fails, the last good snapshot is served
  alongside the error so the dashboard can render stale bars instead of an
  empty card.
  """

  @cache_key {__MODULE__, :cache}
  @forced_min_ms 15_000
  @fetch_timeout 20_000
  @backoff_min_ms 5 * 60_000

  @providers [
    %{id: "claude", module: TokenTracker.Quota.Claude, ttl_ms: 180_000},
    %{id: "codex", module: TokenTracker.Quota.Codex, ttl_ms: 60_000}
  ]

  def report(opts \\ []) do
    force = Keyword.get(opts, :force, false)
    now = System.system_time(:millisecond)
    cache = read_cache()

    cache =
      case Enum.filter(@providers, &due?(cache[&1.id], &1, now, force)) do
        [] -> cache
        due -> refresh(cache, due, now)
      end

    %{
      generated_at: iso(now),
      providers: Enum.map(@providers, &present(cache, &1.id))
    }
  end

  # A provider is due when its backoff window has passed and its snapshot has
  # outlived the provider's TTL — or a forced refresh asks sooner, floored so
  # repeated clicks cannot hammer the endpoints. A backoff is never overridden:
  # retrying into a rate limit only extends it.
  defp due?(entry, provider, now, force) do
    entry = entry || empty_entry()
    ttl = if force, do: @forced_min_ms, else: provider.ttl_ms
    now >= entry.not_before and now - entry.fetched_at >= ttl
  end

  defp refresh(cache, due, now) do
    results =
      due
      |> Task.async_stream(fn provider -> {provider, provider.module.fetch()} end,
        timeout: @fetch_timeout,
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.zip(due)
      |> Enum.map(fn
        {{:ok, result}, _provider} -> result
        {{:exit, _reason}, provider} -> {provider, {:error, "the usage check timed out"}}
      end)

    cache =
      Enum.reduce(results, cache, fn {provider, result}, cache ->
        previous = cache[provider.id] || empty_entry()

        entry =
          case result do
            {:ok, data} ->
              %{data: data, updated_at: now, error: nil, fetched_at: now, not_before: 0}

            {:error, {:rate_limited, retry_after_s, reason}} ->
              backoff = max(retry_after_s * 1_000, @backoff_min_ms)
              %{previous | error: reason, fetched_at: now, not_before: now + backoff}

            {:error, reason} ->
              %{previous | error: reason, fetched_at: now}
          end

        Map.put(cache, provider.id, entry)
      end)

    :persistent_term.put(@cache_key, cache)
    cache
  end

  defp empty_entry do
    %{data: nil, updated_at: nil, error: nil, fetched_at: 0, not_before: 0}
  end

  defp read_cache do
    :persistent_term.get(@cache_key, %{})
  end

  defp present(cache, id) do
    entry = cache[id] || %{empty_entry() | error: "unavailable"}

    base =
      entry.data ||
        %{id: id, label: String.capitalize(id), plan: nil, windows: []}

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
