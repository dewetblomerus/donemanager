defmodule DoneManager.Workers.TaskReconcileWorker do
  @moduledoc """
  Periodic worker that keeps task occurrences reconciled and sends due reminders.

  Cron attempts to enqueue this worker once per minute. Uniqueness across
  incomplete states makes an overrunning reconcile skip later ticks instead of
  piling up work. Generation runs first so a freshly-due occurrence can remind
  on the same tick.
  """

  use Oban.Worker,
    queue: :reconcile,
    max_attempts: 1,
    unique: [
      fields: [:worker],
      period: :infinity,
      states: :incomplete
    ]

  @impl Oban.Worker
  def perform(_job) do
    DoneManager.Tasks.reconcile_occurrences()
    DoneManager.Notifications.send_due_reminders()
  end
end
