defmodule TokenTrackerWeb.QuotaController do
  use Phoenix.Controller, formats: [:json]

  def show(conn, params) do
    force = Map.get(params, "refresh") in ["1", "true"]
    json(conn, TokenTracker.Quota.report(force: force))
  end
end
