defmodule TokenTracker.QuotaTracking do
  @moduledoc """
  Named "trip meter" sessions over the subscription quota percentages.

  Starting a session snapshots every provider window; a sampler records the
  same snapshot every few minutes while the session runs, and stopping records
  a final one. Because a window's percentage falls back to zero when it
  resets, the usage a session consumed is reconstructed from the sample trail
  as the sum of upward moves — a reset shows up as a drop and contributes
  nothing, so climbs on both sides of it are counted. The reconstruction is
  therefore accurate to within whatever was used in the last sampling gap
  before a reset.
  """

  import Ecto.Query

  alias TokenTracker.{Quota, Repo}
  alias TokenTracker.QuotaTracking.{Sample, Session}

  # A window's percentage jitters by rounding between reads; only a fall
  # bigger than this is treated as the window resetting.
  @reset_drop 1.0

  def start(name) do
    name = String.trim(name || "")

    cond do
      name == "" -> {:error, :name_required}
      active_session() != nil -> {:error, :already_active}
      true -> do_start(name)
    end
  end

  defp do_start(name) do
    report = Quota.report(force: true)
    now = DateTime.utc_now()
    session = Repo.insert!(%Session{name: name, started_at: now})
    record(session.id, "start", report, now)
    {:ok, session}
  end

  def stop do
    case active_session() do
      nil ->
        {:error, :not_active}

      session ->
        report = Quota.report(force: true)
        now = DateTime.utc_now()
        record(session.id, "end", report, now)

        session
        |> Ecto.Changeset.change(ended_at: now)
        |> Repo.update!()

        :ok
    end
  end

  def delete(id) do
    case Repo.get(Session, id) do
      nil ->
        {:error, :not_found}

      session ->
        Repo.delete_all(from(sample in Sample, where: sample.session_id == ^session.id))
        Repo.delete!(session)
        :ok
    end
  end

  @doc """
  Records a sampler pass for the active session, if there is one. The quota
  report is asked for without force, so the provider TTLs and rate-limit
  backoffs are honoured; a pass that finds only errors records nothing.
  """
  def sample do
    case active_session() do
      nil -> :idle
      session -> record(session.id, "auto", Quota.report(), DateTime.utc_now())
    end
  end

  def active_session do
    Repo.one(
      from(session in Session,
        where: is_nil(session.ended_at),
        order_by: [desc: session.id],
        limit: 1
      )
    )
  end

  @doc """
  The active session (summarised against the current cached quota, so the
  running tally is as fresh as the last provider check) and the finished
  history, newest first.
  """
  def report do
    sessions = Repo.all(from(session in Session, order_by: [desc: session.started_at]))
    samples = samples_by_session(Enum.map(sessions, & &1.id))
    {active, ended} = Enum.split_with(sessions, &is_nil(&1.ended_at))

    %{
      active:
        case active do
          [session | _rest] ->
            present(session, (samples[session.id] || []) ++ virtual_samples())

          [] ->
            nil
        end,
      history: Enum.map(ended, &present(&1, samples[&1.id] || []))
    }
  end

  defp samples_by_session([]), do: %{}

  defp samples_by_session(ids) do
    Repo.all(
      from(sample in Sample,
        where: sample.session_id in ^ids,
        order_by: [asc: sample.taken_at, asc: sample.id]
      )
    )
    |> Enum.group_by(& &1.session_id)
  end

  defp present(session, samples) do
    %{
      id: session.id,
      name: session.name,
      started_at: DateTime.to_iso8601(session.started_at),
      ended_at: session.ended_at && DateTime.to_iso8601(session.ended_at),
      windows: summarize(samples, session.ended_at != nil)
    }
  end

  @doc """
  Folds a session's chronological sample trail into one summary per provider
  window: the starting and latest percentages, the consumed total (sum of
  upward moves), and how many resets were crossed.
  """
  def summarize(samples, ended?) do
    samples
    |> Enum.group_by(&{&1.provider, &1.window_id})
    |> Enum.map(fn {_key, [first | _rest] = trail} ->
      last = List.last(trail)

      {consumed, resets} =
        trail
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.reduce({0.0, 0}, fn [previous, current], {consumed, resets} ->
          delta = current.used_percent - previous.used_percent

          {
            consumed + max(delta, 0.0),
            resets + if(delta < -@reset_drop, do: 1, else: 0)
          }
        end)

      %{
        provider: first.provider,
        provider_label: last.provider_label || first.provider_label,
        window_id: first.window_id,
        label: last.window_label || first.window_label,
        weekly: last.weekly,
        start_percent: first.used_percent,
        last_percent: last.used_percent,
        end_percent: if(ended?, do: last.used_percent),
        consumed_percent: consumed,
        resets: resets,
        stale: first.stale or last.stale
      }
    end)
    |> Enum.sort_by(&{&1.provider, &1.weekly, &1.window_id})
  end

  # The current cached quota as unsaved samples, appended to an active
  # session's trail so its summary reflects the freshest reading without
  # waiting for the next sampler pass.
  defp virtual_samples do
    snapshot_samples(Quota.report(cached: true), "virtual", DateTime.utc_now())
  end

  defp record(session_id, kind, report, now) do
    rows =
      report
      |> snapshot_samples(kind, now)
      |> Enum.map(
        &(&1
          |> Map.from_struct()
          |> Map.drop([:id, :__meta__])
          |> Map.put(:session_id, session_id))
      )

    if rows != [], do: Repo.insert_all(Sample, rows)
    :ok
  end

  # Flattens a quota report into `Sample` structs. Provider data fetched this
  # boot is atom-keyed, while data reloaded from the disk cache after a
  # restart is string-keyed, so every field is read tolerantly.
  defp snapshot_samples(report, kind, now) do
    for provider <- field(report, :providers) || [],
        windows = field(provider, :windows) || [],
        windows != [],
        window <- windows do
      %Sample{
        kind: kind,
        taken_at: now,
        provider: to_string(field(provider, :id)),
        provider_label: field(provider, :label),
        window_id: to_string(field(window, :id)),
        window_label: field(window, :label),
        weekly: field(window, :weekly) == true,
        used_percent: (field(window, :used_percent) || 0) * 1.0,
        resets_at: field(window, :resets_at),
        stale: field(provider, :stale) == true
      }
    end
  end

  defp field(map, key) when is_map(map) do
    case map do
      %{^key => value} -> value
      _other -> Map.get(map, Atom.to_string(key))
    end
  end

  defp field(_other, _key), do: nil
end
