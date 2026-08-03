defmodule TokenTrackerWeb.FxController do
  use Phoenix.Controller, formats: [:json]

  def show(conn, _params), do: json(conn, %{eur_per_usd: TokenTracker.Fx.eur_per_usd()})
end
