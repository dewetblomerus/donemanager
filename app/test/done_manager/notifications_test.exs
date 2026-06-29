defmodule DoneManager.NotificationsTest do
  use DoneManager.DataCase, async: true

  import DoneManager.AccountsFixtures
  import DoneManager.HouseholdsFixtures
  import DoneManager.TasksFixtures

  alias DoneManager.Accounts
  alias DoneManager.Households.HouseholdMembership
  alias DoneManager.Notifications
  alias DoneManager.Notifications.NotificationDelivery
  alias DoneManager.Repo
  alias DoneManager.Tasks

  @now ~U[2026-06-29 12:00:00.000000Z]
  @past ~U[2026-06-29 11:00:00.000000Z]

  setup do
    scope = owner_scope_fixture()
    {:ok, owner} = Accounts.update_user_settings(scope.user, %{pushover_user_key: "u-owner"})
    stub_pushover()
    %{scope: scope, owner: owner}
  end

  describe "send_due_reminders/1" do
    test "reminds each member with a key for a due occurrence and upserts a row", %{
      scope: scope,
      owner: owner
    } do
      task = interval_task(scope)
      occ = set_due_at(task, @past)

      assert :ok = Notifications.send_due_reminders(@now)

      assert_received {:pushover, params}
      assert params["user"] == "u-owner"
      assert params["title"] == task.name

      delivery = get_delivery(occ.id, owner.id)
      assert delivery.notification_type == "reminder"
      assert delivery.reminder_count == 1
      assert delivery.last_status == "ok"
    end

    test "does not remind a member without a Pushover key", %{scope: scope} do
      keyless = add_member(scope)
      task = interval_task(scope)
      occ = set_due_at(task, @past)

      Notifications.send_due_reminders(@now)

      assert get_delivery(occ.id, keyless.id) == nil
    end

    test "a null reminder_interval_minutes means a single reminder", %{scope: scope, owner: owner} do
      task = interval_task(scope)
      occ = set_due_at(task, @past)

      Notifications.send_due_reminders(@now)
      Notifications.send_due_reminders(DateTime.add(@now, 60, :minute))

      assert get_delivery(occ.id, owner.id).reminder_count == 1
    end

    test "re-reminds once the interval has elapsed", %{scope: scope, owner: owner} do
      task = interval_task(scope) |> set_reminder_interval(30)
      occ = set_due_at(task, @past)

      Notifications.send_due_reminders(@now)
      Notifications.send_due_reminders(DateTime.add(@now, 10, :minute))
      assert get_delivery(occ.id, owner.id).reminder_count == 1

      Notifications.send_due_reminders(DateTime.add(@now, 31, :minute))
      assert get_delivery(occ.id, owner.id).reminder_count == 2
    end

    test "reminds a timer occurrence whose due_at has passed", %{scope: scope, owner: owner} do
      task =
        task_fixture(scope, %{
          "name" => "Move the laundry",
          "task_type" => "timer",
          "interval_minutes" => 60
        })

      occ = set_due_at(task, @past)

      Notifications.send_due_reminders(@now)

      assert get_delivery(occ.id, owner.id).reminder_count == 1
    end

    test "does not remind a completed occurrence", %{scope: scope, owner: owner} do
      task = interval_task(scope)
      occ = task |> set_due_at(@past) |> complete()

      Notifications.send_due_reminders(@now)

      assert get_delivery(occ.id, owner.id) == nil
    end

    test "does not remind an expired occurrence", %{scope: scope, owner: owner} do
      task = interval_task(scope)
      # expired: expires_at in the past
      occ =
        task
        |> set_due_at(@past)
        |> Ecto.Changeset.change(expires_at: @past)
        |> Repo.update!()

      Notifications.send_due_reminders(@now)

      assert get_delivery(occ.id, owner.id) == nil
    end

    test "sends at priority -1 during the recipient's quiet hours", %{scope: scope, owner: owner} do
      {:ok, _} =
        Accounts.update_user_settings(owner, %{
          quiet_hours_start: ~T[08:00:00],
          quiet_hours_end: ~T[18:00:00]
        })

      task = interval_task(scope)
      set_due_at(task, @past)

      # @now is 12:00 UTC, inside 08:00–18:00 in the Etc/UTC household
      Notifications.send_due_reminders(@now)

      assert_received {:pushover, params}
      assert params["priority"] == "-1"
    end

    test "sends at normal priority outside quiet hours", %{scope: scope} do
      task = interval_task(scope)
      set_due_at(task, @past)

      Notifications.send_due_reminders(@now)

      assert_received {:pushover, params}
      refute Map.has_key?(params, "priority")
    end
  end

  defp interval_task(scope) do
    task_fixture(scope, %{
      "name" => "Let the dog out",
      "task_type" => "interval",
      "interval_minutes" => 180
    })
  end

  defp set_due_at(task, due_at) do
    task
    |> Tasks.current_occurrence()
    |> Ecto.Changeset.change(due_at: due_at)
    |> Repo.update!()
  end

  defp complete(occurrence) do
    occurrence
    |> Ecto.Changeset.change(completed_at: @past)
    |> Repo.update!()
  end

  defp set_reminder_interval(task, minutes) do
    task
    |> Ecto.Changeset.change(reminder_interval_minutes: minutes)
    |> Repo.update!()
  end

  defp add_member(scope) do
    user = user_fixture()

    Repo.insert!(%HouseholdMembership{
      household_id: scope.household.id,
      user_id: user.id,
      role: "member"
    })

    user
  end

  defp get_delivery(occurrence_id, user_id) do
    Repo.get_by(NotificationDelivery,
      task_occurrence_id: occurrence_id,
      user_id: user_id,
      notification_type: "reminder"
    )
  end

  defp stub_pushover do
    Req.Test.stub(DoneManager.Pushover, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:pushover, URI.decode_query(body)})
      Req.Test.json(conn, %{"status" => 1})
    end)
  end
end
