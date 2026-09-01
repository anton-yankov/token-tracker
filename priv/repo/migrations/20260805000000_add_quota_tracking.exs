defmodule TokenTracker.Repo.Migrations.AddQuotaTracking do
  use Ecto.Migration

  def change do
    create table(:quota_tracking_sessions) do
      add(:name, :string, null: false)
      add(:started_at, :utc_datetime_usec, null: false)
      add(:ended_at, :utc_datetime_usec)
    end

    create(index(:quota_tracking_sessions, [:ended_at]))

    create table(:quota_tracking_samples) do
      add(
        :session_id,
        references(:quota_tracking_sessions, on_delete: :delete_all),
        null: false
      )

      add(:kind, :string, null: false)
      add(:taken_at, :utc_datetime_usec, null: false)
      add(:provider, :string, null: false)
      add(:provider_label, :string)
      add(:window_id, :string, null: false)
      add(:window_label, :string)
      add(:weekly, :boolean, null: false, default: false)
      add(:used_percent, :float, null: false)
      add(:resets_at, :string)
      add(:stale, :boolean, null: false, default: false)
    end

    create(index(:quota_tracking_samples, [:session_id]))
  end
end
