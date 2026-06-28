defmodule DoneManagerWeb.OccurrenceHTML do
  @moduledoc """
  The occurrence page rendered after a tap (or a direct visit). It is the
  confirmation the person sees — the page *is* the ack.
  """

  use DoneManagerWeb, :html

  alias DoneManager.Timezones

  def show(assigns) do
    ~H"""
    <Layouts.execution flash={@flash}>
      <div class="space-y-5">
        <div class="flex items-start justify-between gap-4">
          <h1 class="text-2xl font-semibold leading-tight text-base-content">
            {@occurrence.task.name}
          </h1>
          <.link
            navigate={~p"/tasks/#{@occurrence.task}"}
            class="btn btn-sm btn-ghost shrink-0"
          >
            View task
          </.link>
        </div>

        <div class={[
          "rounded-lg p-6 shadow-sm",
          @outcome == :duplicate && "bg-red-900 text-white",
          @occurrence.completed_at && @outcome != :duplicate && "bg-success text-success-content",
          !@occurrence.completed_at && "bg-base-100 text-base-content"
        ]}>
          <p class="text-4xl font-bold leading-none">
            {status_label(@occurrence, @outcome)}
          </p>
          <p :if={@occurrence.completed_at} class="mt-4 text-lg font-medium leading-7 opacity-90">
            Completed by {completed_by(@occurrence)} at {completed_at(@occurrence)}
          </p>
        </div>
      </div>
    </Layouts.execution>
    """
  end

  defp status_label(%{completed_at: %DateTime{}}, :duplicate), do: "Already done"
  defp status_label(%{completed_at: %DateTime{}}, _outcome), do: "done"
  defp status_label(_occurrence, _outcome), do: "open"

  defp completed_at(%{completed_at: completed_at, task: %{household: %{timezone: timezone}}}) do
    Timezones.format(completed_at, timezone)
  end

  defp completed_by(%{completed_by: nil}), do: "a household member"
  defp completed_by(%{completed_by: user}), do: user.display_name || user.email
end
