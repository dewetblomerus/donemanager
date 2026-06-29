defmodule DoneManager.Workers.TaskReconcileWorker do
  @moduledoc """
  Periodic worker that keeps task occurrences reconciled.

  Cron attempts to enqueue this worker once per minute. Uniqueness across
  incomplete states makes an overrunning reconcile skip later ticks instead of
  piling up work.
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
  end
end
