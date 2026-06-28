defmodule DoneManagerWeb.ScanControllerTest do
  use DoneManagerWeb.ConnCase, async: true

  import DoneManager.AutomationFixtures
  import DoneManager.HouseholdsFixtures
  import DoneManager.IntegrationsFixtures
  import DoneManager.TasksFixtures

  alias DoneManager.Tasks

  setup do
    scope = owner_scope_fixture()
    {_token, plaintext} = token_fixture(scope)
    %{scope: scope, plaintext: plaintext}
  end

  defp scan(conn, plaintext, external_id) do
    post(conn, ~p"/v1/tags/#{external_id}/scans", %{access_token: plaintext})
  end

  test "scanning an assigned tag completes the open occurrence end to end", %{
    scope: scope,
    plaintext: plaintext,
    conn: conn
  } do
    task = task_fixture(scope, %{"name" => "Spot breakfast"})
    tag = tag_fixture(scope)
    command_fixture(scope, task, tag)

    conn = scan(conn, plaintext, tag.external_id)

    assert %{"outcome" => "completed", "task" => "Spot breakfast", "occurrence_status" => status} =
             json_response(conn, 200)

    assert status["done_by"]
    assert Tasks.done?(Tasks.current_occurrence(task))
  end

  test "a second scan reports a duplicate without undoing", %{
    scope: scope,
    plaintext: plaintext,
    conn: conn
  } do
    task = task_fixture(scope)
    tag = tag_fixture(scope)
    command_fixture(scope, task, tag)

    scan(conn, plaintext, tag.external_id)
    conn = scan(build_conn(), plaintext, tag.external_id)

    assert %{"outcome" => "duplicate_completion_attempted"} = json_response(conn, 200)
    assert Tasks.done?(Tasks.current_occurrence(task))
  end

  test "first scan of an unknown tag registers it", %{plaintext: plaintext, conn: conn} do
    conn = scan(conn, plaintext, UUIDv7.generate())
    assert %{"outcome" => "tag_registered"} = json_response(conn, 200)
  end

  test "a registered tag with no command is unassigned", %{
    scope: scope,
    plaintext: plaintext,
    conn: conn
  } do
    tag = tag_fixture(scope)
    conn = scan(conn, plaintext, tag.external_id)
    assert %{"outcome" => "tag_unassigned"} = json_response(conn, 200)
  end

  test "a malformed external_id is a 400", %{plaintext: plaintext, conn: conn} do
    conn = scan(conn, plaintext, "not-a-uuid")
    assert json_response(conn, 400)
  end

  test "a missing or bad token is a 401", %{conn: conn} do
    no_token = post(conn, ~p"/v1/tags/#{UUIDv7.generate()}/scans")
    assert json_response(no_token, 401)

    bad = scan(build_conn(), "bogus.token", UUIDv7.generate())
    assert json_response(bad, 401)
  end

  test "an authorization header without an access_token param is a 401", %{
    plaintext: plaintext,
    conn: conn
  } do
    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> plaintext)
      |> post(~p"/v1/tags/#{UUIDv7.generate()}/scans")

    assert json_response(conn, 401)
  end
end
