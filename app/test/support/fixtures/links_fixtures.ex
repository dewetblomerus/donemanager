defmodule DoneManager.LinksFixtures do
  @moduledoc "Test fixtures for the Links context."

  alias DoneManager.Accounts.Scope
  alias DoneManager.Links
  alias DoneManager.Links.Link
  alias DoneManager.Tasks.Task

  @doc "A link in the scope's household."
  def link_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, link} = Links.create_link(scope, Enum.into(attrs, %{"label" => "Kitchen"}))
    link
  end

  @doc "Binds `task` to `link`."
  def bind_fixture(%Scope{} = scope, %Link{} = link, %Task{} = task) do
    {:ok, link_task} = Links.bind_task(scope, link, task.id)
    link_task
  end
end
