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

  def link_status(assigns) do
    ~H"""
    <Layouts.execution flash={@flash}>
      <div class="space-y-5">
        <div class="rounded-lg bg-warning p-6 text-warning-content shadow-sm">
          <p class="text-3xl font-bold leading-tight">{status_page_title(@context)}</p>
          <p
            :if={@context.outside_execution_hours}
            class="mt-3 text-lg font-medium leading-7 opacity-90"
          >
            This tag is assigned, but it is not in an execution window right now.
          </p>
        </div>

        <div class="space-y-3">
          <.warning_occurrence
            :if={@context.previous}
            title="Previous occurrence"
            occurrence={@context.previous}
            status={occurrence_status_label(@context.previous)}
          />
          <.warning_occurrence
            :if={@context.next}
            title="Next occurrence"
            occurrence={@context.next}
            status="Too early"
          />
        </div>
      </div>
    </Layouts.execution>
    """
  end

  def scan_warning(assigns), do: link_status(assigns)

  attr :title, :string, required: true
  attr :occurrence, :map, required: true
  attr :status, :string, required: true

  defp warning_occurrence(assigns) do
    ~H"""
    <div class="rounded-lg bg-warning p-5 text-warning-content shadow-sm">
      <p class="text-sm font-semibold uppercase opacity-75">{@title}</p>
      <div class="mt-2 flex items-start justify-between gap-3">
        <div>
          <p class="text-xl font-semibold leading-tight">{@occurrence.task.name}</p>
          <p :if={@occurrence.completed_at} class="mt-2 text-sm font-medium leading-6 opacity-80">
            Completed by {completed_by(@occurrence)} at {completed_at(@occurrence)}
          </p>
        </div>
        <p class="shrink-0 text-lg font-bold leading-tight">{@status}</p>
      </div>
    </div>
    """
  end

  defp status_label(%{completed_at: %DateTime{}}, :duplicate), do: "Already done"
  defp status_label(%{completed_at: %DateTime{}}, _outcome), do: "done"
  defp status_label(_occurrence, _outcome), do: "open"

  defp status_page_title(%{outside_execution_hours: true}), do: "Outside task hours"
  defp status_page_title(_context), do: "Link status"

  defp occurrence_status_label(%{completed_at: %DateTime{}}), do: "done"

  defp occurrence_status_label(%{expires_at: %DateTime{} = expires_at}) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :lt do
      "expired"
    else
      "open"
    end
  end

  defp occurrence_status_label(_occurrence), do: "open"

  defp completed_at(%{completed_at: completed_at, task: %{household: %{timezone: timezone}}}) do
    Timezones.format(completed_at, timezone)
  end

  defp completed_by(%{completed_by: nil}), do: "a household member"
  defp completed_by(%{completed_by: user}), do: user.display_name || user.email
end
