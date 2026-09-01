defmodule TokenTracker.QuotaTrackingTest do
  use ExUnit.Case, async: true

  alias TokenTracker.{QuotaTracking, Repo}
  alias TokenTracker.QuotaTracking.{Sample, Session}

  defp sample(percent, minute, overrides \\ []) do
    struct!(
      %Sample{
        kind: "auto",
        taken_at: DateTime.add(~U[2026-08-05 10:00:00.000000Z], minute, :minute),
        provider: "claude",
        provider_label: "Claude",
        window_id: "session",
        window_label: "5-hour limit",
        weekly: false,
        used_percent: percent * 1.0,
        stale: false
      },
      overrides
    )
  end

  test "a plain climb consumes end minus start" do
    [window] = QuotaTracking.summarize([sample(10, 0), sample(14, 12), sample(25, 24)], true)

    assert window.start_percent == 10.0
    assert window.end_percent == 25.0
    assert window.consumed_percent == 15.0
    assert window.resets == 0
  end

  test "a reset mid-session combines the climbs on both sides" do
    samples = [sample(60, 0), sample(85, 12), sample(3, 24), sample(25, 36)]
    [window] = QuotaTracking.summarize(samples, true)

    assert window.consumed_percent == 47.0
    assert window.resets == 1
  end

  test "rounding jitter is neither consumption nor a reset" do
    [window] = QuotaTracking.summarize([sample(37, 0), sample(36.5, 12), sample(37, 24)], true)

    assert window.consumed_percent == 0.5
    assert window.resets == 0
  end

  test "an active session reports the latest reading without an end" do
    [window] = QuotaTracking.summarize([sample(10, 0), sample(14, 12)], false)

    assert window.last_percent == 14.0
    assert window.end_percent == nil
  end

  test "windows group per provider and id, stale marks surface" do
    samples = [
      sample(10, 0),
      sample(40, 0, provider: "codex", provider_label: "Codex", window_id: "primary"),
      sample(12, 12, stale: true),
      sample(41, 12, provider: "codex", provider_label: "Codex", window_id: "primary")
    ]

    [claude, codex] = QuotaTracking.summarize(samples, true)

    assert claude.provider == "claude"
    assert claude.stale
    assert codex.provider == "codex"
    assert codex.consumed_percent == 1.0
    refute codex.stale
  end

  test "report splits active from history and delete removes a session" do
    ended =
      Repo.insert!(%Session{
        name: "finished work",
        started_at: ~U[2026-08-05 08:00:00.000000Z],
        ended_at: ~U[2026-08-05 09:00:00.000000Z]
      })

    active =
      Repo.insert!(%Session{name: "running work", started_at: ~U[2026-08-05 10:00:00.000000Z]})

    for {session, minute} <- [{ended, 0}, {ended, 60}, {active, 120}] do
      row =
        sample(10 + minute / 60, minute)
        |> Map.from_struct()
        |> Map.drop([:id, :__meta__])
        |> Map.put(:session_id, session.id)

      Repo.insert_all(Sample, [row])
    end

    report = QuotaTracking.report()

    assert report.active.name == "running work"
    assert [%{name: "finished work", windows: [window]}] = report.history
    assert window.consumed_percent == 1.0

    assert :ok = QuotaTracking.delete(ended.id)
    assert {:error, :not_found} = QuotaTracking.delete(ended.id)
    assert %{history: []} = QuotaTracking.report()

    Repo.delete_all(Sample)
    Repo.delete_all(Session)
  end
end
