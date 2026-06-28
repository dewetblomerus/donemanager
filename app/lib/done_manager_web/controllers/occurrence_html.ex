defmodule DoneManagerWeb.OccurrenceHTML do
  @moduledoc """
  The occurrence page rendered after a tap (or a direct visit). It is the
  confirmation the person sees — the page *is* the ack.
  """

  use DoneManagerWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@occurrence.task.name}
        <:subtitle>
          {headline(@outcome)}
        </:subtitle>
      </.header>

      <div class="mt-4 flex items-center gap-3">
        <span class={["badge", @occurrence.completed_at && "badge-success"]}>
          {if @occurrence.completed_at, do: "done", else: "open"}
        </span>
        <span :if={@occurrence.completed_at} class="opacity-70">
          Completed by {completed_by(@occurrence)}
        </span>
      </div>

      <.button class="mt-6" navigate={~p"/tasks/#{@occurrence.task}"}>View task</.button>
    </Layouts.app>
    """
  end

  defp headline(:completed), do: "Marked done. Thanks!"
  defp headline(:duplicate), do: "Already done."
  defp headline(_), do: nil

  defp completed_by(%{completed_by: nil}), do: "a household member"
  defp completed_by(%{completed_by: user}), do: user.display_name || user.email
end
