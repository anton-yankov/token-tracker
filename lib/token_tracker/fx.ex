defmodule TokenTracker.Fx do
  @moduledoc """
  EUR/USD reference rate for pricing display.

  Model prices come from the catalog in USD; the dashboard shows euro. The
  ECB's daily reference feed is fetched at most twice a day, cached in a
  persistent term, and a recent flat fallback covers a cold start with no
  network. Failed fetches retry after a few minutes rather than on every
  request.
  """

  @url "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"
  @cache_key {__MODULE__, :rate}
  @ttl_ms 12 * 3_600_000
  @retry_ms 5 * 60_000
  @fallback_eur_per_usd 0.86

  def eur_per_usd do
    now = System.system_time(:millisecond)

    case :persistent_term.get(@cache_key, nil) do
      %{rate: rate, at: at} when now - at < @ttl_ms ->
        rate

      cached ->
        refresh(cached, now)
    end
  end

  defp refresh(cached, now) do
    case fetch() do
      {:ok, rate} ->
        :persistent_term.put(@cache_key, %{rate: rate, at: now})
        rate

      :error ->
        rate = (cached && cached.rate) || @fallback_eur_per_usd
        :persistent_term.put(@cache_key, %{rate: rate, at: now - @ttl_ms + @retry_ms})
        rate
    end
  end

  defp fetch do
    case Req.get(@url,
           retry: false,
           connect_options: [timeout: 10_000],
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        parse(body)

      _ ->
        :error
    end
  end

  defp parse(body) do
    with [_, raw] <- Regex.run(~r/currency='USD'\s+rate='([\d.]+)'/, body),
         {usd_per_eur, _rest} when usd_per_eur > 0 <- Float.parse(raw) do
      {:ok, 1.0 / usd_per_eur}
    else
      _ -> :error
    end
  end
end
