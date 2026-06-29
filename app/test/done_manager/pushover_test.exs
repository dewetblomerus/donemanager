defmodule DoneManager.PushoverTest do
  use ExUnit.Case, async: true

  alias DoneManager.Pushover

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end

  test "returns :ok when Pushover accepts the message" do
    Req.Test.stub(Pushover, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)

      assert params["token"] == "test-token"
      assert params["user"] == "u-abc123"
      assert params["message"] == "Hello"
      assert params["title"] == "Done Manager"

      Req.Test.json(conn, %{"status" => 1, "request" => "abc"})
    end)

    assert :ok = Pushover.send_message("u-abc123", "Hello", title: "Done Manager")
  end

  test "returns an error when Pushover rejects the request" do
    Req.Test.stub(Pushover, fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{"status" => 0, "errors" => ["user key is invalid"]})
    end)

    assert {:error, {:pushover, 400, %{"status" => 0}}} = Pushover.send_message("bad", "Hello")
  end

  test "short-circuits when no user key is set" do
    assert {:error, :no_user_key} = Pushover.send_message(nil, "Hello")
    assert {:error, :no_user_key} = Pushover.send_message("", "Hello")
  end
end
