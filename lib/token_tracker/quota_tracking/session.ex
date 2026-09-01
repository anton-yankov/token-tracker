defmodule TokenTracker.QuotaTracking.Session do
  use Ecto.Schema

  schema "quota_tracking_sessions" do
    field(:name, :string)
    field(:started_at, :utc_datetime_usec)
    field(:ended_at, :utc_datetime_usec)
  end
end
