defmodule TokenTracker.QuotaTracking.Sample do
  use Ecto.Schema

  schema "quota_tracking_samples" do
    field(:session_id, :integer)
    field(:kind, :string)
    field(:taken_at, :utc_datetime_usec)
    field(:provider, :string)
    field(:provider_label, :string)
    field(:window_id, :string)
    field(:window_label, :string)
    field(:weekly, :boolean)
    field(:used_percent, :float)
    field(:resets_at, :string)
    field(:stale, :boolean)
  end
end
