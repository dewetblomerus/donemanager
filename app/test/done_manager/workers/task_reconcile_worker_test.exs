defmodule DoneManager.Workers.TaskReconcileWorkerTest do
  use DoneManager.DataCase, async: true
  use Oban.Testing, repo: DoneManager.Repo

  import DoneManager.HouseholdsFixtures
  import DoneManager.TasksFixtures

  alias DoneManager.Tasks
  alias DoneManager.Workers.TaskReconcileWorker

  describe "options" do
    test "uses the reconcile queue, no retries, and worker-level uniqueness" do
      changeset = TaskReconcileWorker.new(%{})

      assert Ecto.Changeset.get_field(changeset, :queue) == "reconcile"
      assert Ecto.Changeset.get_field(changeset, :max_attempts) == 1

      assert %{
               fields: [:worker],
               period: :infinity,
               states: [:suspended, :available, :scheduled, :executing, :retryable]
             } = Ecto.Changeset.get_field(changeset, :unique)
    end
  end

  describe "perform/1" do
    test "reconciles task occurrences" do
      scope = owner_scope_fixture()
      task = task_fixture(scope)
      occurrence = Tasks.current_occurrence(task)
      assert {:ok, _occurrence} = Repo.delete(occurrence)

      assert :ok = perform_job(TaskReconcileWorker, %{})
      assert Tasks.current_occurrence(task)
    end
  end
end
