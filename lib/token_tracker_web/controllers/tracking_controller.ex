defmodule TokenTrackerWeb.TrackingController do
  use Phoenix.Controller, formats: [:json]

  alias TokenTracker.QuotaTracking

  def index(conn, _params) do
    json(conn, QuotaTracking.report())
  end

  # The endpoint has no body parser; the name travels as a query parameter
  # like every other API input.
  def start(conn, params) do
    case QuotaTracking.start(Map.get(params, "name", "")) do
      {:ok, _session} -> json(conn, QuotaTracking.report())
      {:error, :name_required} -> error(conn, 400, "a session name is required")
      {:error, :already_active} -> error(conn, 409, "a tracking session is already active")
    end
  end

  def stop(conn, _params) do
    case QuotaTracking.stop() do
      :ok -> json(conn, QuotaTracking.report())
      {:error, :not_active} -> error(conn, 409, "no tracking session is active")
    end
  end

  def delete(conn, %{"id" => id}) do
    with {parsed, ""} <- Integer.parse(id),
         :ok <- QuotaTracking.delete(parsed) do
      json(conn, QuotaTracking.report())
    else
      _other -> error(conn, 404, "no such tracking session")
    end
  end

  defp error(conn, status, message) do
    conn |> put_status(status) |> json(%{error: message})
  end
end
