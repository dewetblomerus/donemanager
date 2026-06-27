defmodule DoneManager.AutomationTest do
  use DoneManager.DataCase, async: true

  import DoneManager.AutomationFixtures
  import DoneManager.HouseholdsFixtures
  import DoneManager.IntegrationsFixtures
  import DoneManager.TasksFixtures

  alias DoneManager.Automation
  alias DoneManager.Integrations

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
