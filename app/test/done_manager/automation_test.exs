defmodule DoneManager.AutomationTest do
  use DoneManager.DataCase, async: true

  import Ecto.Query
  import DoneManager.AutomationFixtures
  import DoneManager.HouseholdsFixtures
  import DoneManager.IntegrationsFixtures
  import DoneManager.TasksFixtures

  alias DoneManager.Automation
  alias DoneManager.Integrations
  alias DoneManager.Tasks
  alias DoneManager.Tasks.TaskOccurrence

  describe "tags in the UI" do
    test "list_tags_with_assignment shows each tag's assigned task" do
      scope = owner_scope_fixture()
      task = task_fixture(scope)
      assigned = tag_fixture(scope, label: "Kitchen")
      _unassigned = tag_fixture(scope, label: "Garage")
      command_fixture(scope, task, assigned)

      tags = Automation.list_tags_with_assignment(scope)
      assert length(tags) == 2

      by_label = Map.new(tags, &{&1.label, &1})
      assert [command] = by_label["Kitchen"].automation_commands
      assert command.task.id == task.id
      assert by_label["Garage"].automation_commands == []
    end

    test "a scan records who last scanned the tag (from the token's user)" do
      scope = owner_scope_fixture()
      {_token, plaintext} = token_fixture(scope)
      {:ok, authed} = Integrations.authenticate(plaintext)

      external_id = "0190c0de-1234-7abc-8def-0123456789ab"
      {:ok, _outcome} = Automation.handle_scan(authed, external_id)

      [tag] = Automation.list_tags_with_assignment(scope)
      assert tag.last_scanned_at
      assert tag.last_scanned_by.id == scope.user.id
    end

    test "scanning a timer task's tag is derived as a (not-yet-enabled) timer toggle" do
      scope = owner_scope_fixture()

      {:ok, task} =
        Tasks.create_task(scope, %{
          "name" => "Laundry",
          "task_type" => "timer",
          "timer_minutes" => "60"
        })

      tag = tag_fixture(scope)
      assert {:ok, command} = Automation.assign_tag(scope, task, tag.id)
      assert command.task_id == task.id

      # Behavior is derived from the task type at scan time, not stored.
      {_token, plaintext} = token_fixture(scope)
      {:ok, authed} = Integrations.authenticate(plaintext)

      assert {:ok, %{outcome: "timer_not_enabled"}} =
               Automation.handle_scan(authed, tag.external_id)
    end

    test "one tag can route to different tasks by time of day" do
      scope = owner_scope_fixture()

      breakfast =
        task_fixture(scope, %{
          "name" => "Dog breakfast",
          "due_time" => "08:00:00",
          "scan_window_start_time" => "05:00",
          "scan_window_end_time" => "11:00"
        })

      dinner =
        task_fixture(scope, %{
          "name" => "Dog dinner",
          "due_time" => "18:00:00",
          "scan_window_start_time" => "17:00",
          "scan_window_end_time" => "23:00"
        })

      tag = tag_fixture(scope)

      command_fixture(scope, breakfast, tag)
      command_fixture(scope, dinner, tag)

      {_token, plaintext} = token_fixture(scope)
      {:ok, authed} = Integrations.authenticate(plaintext)

      assert {:ok, %{outcome: "completed", task: "Dog breakfast"}} =
               Automation.handle_scan(authed, tag.external_id, ~U[2026-06-27 08:00:00.000000Z])

      assert {:ok, %{outcome: "completed", task: "Dog dinner"}} =
               Automation.handle_scan(authed, tag.external_id, ~U[2026-06-27 18:00:00.000000Z])
    end

    test "a tag with no task scan window matching the scan time is unassigned" do
      scope = owner_scope_fixture()

      breakfast =
        task_fixture(scope, %{
          "name" => "Dog breakfast",
          "due_time" => "08:00:00",
          "scan_window_start_time" => "05:00",
          "scan_window_end_time" => "11:00"
        })

      tag = tag_fixture(scope)
      command_fixture(scope, breakfast, tag)

      {_token, plaintext} = token_fixture(scope)
      {:ok, authed} = Integrations.authenticate(plaintext)

      assert {:ok, %{outcome: "tag_unassigned", task: nil}} =
               Automation.handle_scan(authed, tag.external_id, ~U[2026-06-27 14:00:00.000000Z])
    end

    test "shared tag windows complete the first open occurrence by due time" do
      scope = owner_scope_fixture()

      breakfast =
        task_fixture(scope, %{
          "name" => "Dog breakfast",
          "due_time" => "08:00:00",
          "scan_window_start_time" => "05:00",
          "scan_window_end_time" => "23:00"
        })

      dinner =
        task_fixture(scope, %{
          "name" => "Dog dinner",
          "due_time" => "18:00:00",
          "scan_window_start_time" => "05:00",
          "scan_window_end_time" => "23:00"
        })

      tag = tag_fixture(scope)

      breakfast_occurrence = Tasks.current_occurrence(breakfast)
      dinner_occurrence = Tasks.current_occurrence(dinner)

      breakfast_occurrence
      |> Ecto.Changeset.change(due_at: ~U[2026-06-27 08:00:00.000000Z])
      |> Repo.update!()

      dinner_occurrence
      |> Ecto.Changeset.change(due_at: ~U[2026-06-27 18:00:00.000000Z])
      |> Repo.update!()

      assert {:ok, _command} = Automation.assign_tag(scope, breakfast, tag.id)
      assert {:ok, _command} = Automation.assign_tag(scope, dinner, tag.id)

      {_token, plaintext} = token_fixture(scope)
      {:ok, authed} = Integrations.authenticate(plaintext)

      assert {:ok, %{outcome: "completed", task: "Dog breakfast"}} =
               Automation.handle_scan(authed, tag.external_id, ~U[2026-06-27 19:00:00.000000Z])

      assert Tasks.done?(Tasks.current_occurrence(breakfast))
      refute Tasks.done?(Tasks.current_occurrence(dinner))

      assert {:ok, %{outcome: "completed", task: "Dog dinner"}} =
               Automation.handle_scan(authed, tag.external_id, ~U[2026-06-27 19:01:00.000000Z])

      assert Tasks.done?(Tasks.current_occurrence(dinner))
    end

    test "update_tag renames a tag in the scope's household" do
      scope = owner_scope_fixture()
      tag = tag_fixture(scope, label: "Old")

      assert {:ok, renamed} = Automation.update_tag(scope, tag, %{"label" => "New"})
      assert renamed.label == "New"
    end

    test "update_tag rejects a tag from another household" do
      scope = owner_scope_fixture()
      tag = tag_fixture(scope)
      other = owner_scope_fixture()

      assert {:error, :unauthorized} = Automation.update_tag(other, tag, %{"label" => "Hijack"})
    end

    test "delete_tag removes the row and cascades its command; a re-scan re-registers" do
      scope = owner_scope_fixture()
      task = task_fixture(scope)
      tag = tag_fixture(scope, label: "Kitchen")
      command_fixture(scope, task, tag)

      assert {:ok, _} = Automation.delete_tag(scope, tag)
      assert Automation.list_tags(scope) == []
      assert Automation.list_commands_for_task(task) == []

      # A later scan of the same external_id simply re-registers the tag.
      {_token, plaintext} = token_fixture(scope)
      {:ok, authed} = Integrations.authenticate(plaintext)
      {:ok, %{outcome: "tag_registered"}} = Automation.handle_scan(authed, tag.external_id)
      assert [readded] = Automation.list_tags(scope)
      assert readded.external_id == tag.external_id
    end

    test "a scan completes even when the task has no current occurrence (self-heals)" do
      scope = owner_scope_fixture()
      task = task_fixture(scope)
      tag = tag_fixture(scope)
      command_fixture(scope, task, tag)

      # Simulate a task that has lost its occurrence; the scan must not 500.
      Repo.delete_all(from o in TaskOccurrence, where: o.task_id == ^task.id)
      refute Tasks.current_occurrence(task)

      {_token, plaintext} = token_fixture(scope)
      {:ok, authed} = Integrations.authenticate(plaintext)

      assert {:ok, %{outcome: "completed"}} = Automation.handle_scan(authed, tag.external_id)
      assert Tasks.done?(Tasks.current_occurrence(task))
    end

    test "delete_tag rejects a tag from another household" do
      scope = owner_scope_fixture()
      tag = tag_fixture(scope)
      other = owner_scope_fixture()

      assert {:error, :unauthorized} = Automation.delete_tag(other, tag)
    end

    test "get_tag! is default-deny across households" do
      scope = owner_scope_fixture()
      tag = tag_fixture(scope)
      stranger = owner_scope_fixture()

      assert_raise Ecto.NoResultsError, fn -> Automation.get_tag!(stranger, tag.id) end
    end
  end
end
