defmodule TokenTracker.QuotaTracking.Sampler do
  @moduledoc """
  Records quota samples for the active tracking session.

  The tick is permanent but cheap: with no active session a pass is a single
  indexed query and no provider is contacted, so quota fetch pressure stays
  user-paced except while a session runs. Living in the supervision tree
  (rather than being started per session) also means a session that was
  active when the service restarted resumes sampling by itself.
  """

  use GenServer

  require Logger

  @interval_ms 12 * 60_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(nil) do
    schedule()
    {:ok, nil}
  end

  @impl true
  def handle_info(:tick, state) do
    TokenTracker.QuotaTracking.sample()
    schedule()
    {:noreply, state}
  rescue
    error ->
      Logger.warning("quota tracking sample failed: #{Exception.message(error)}")
      schedule()
      {:noreply, state}
  end

  defp schedule do
    Process.send_after(self(), :tick, @interval_ms)
  end
end
