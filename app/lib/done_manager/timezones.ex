defmodule DoneManager.Timezones do
  @moduledoc """
  A curated list of canonical IANA timezone names offered when configuring a
  household. Kept small and hand-picked rather than pulling a full timezone
  database dependency; extend as households need more zones.
  """

  @timezones [
    "Etc/UTC",
    "Africa/Cairo",
    "Africa/Johannesburg",
    "Africa/Lagos",
    "Africa/Nairobi",
    "America/Anchorage",
    "America/Argentina/Buenos_Aires",
    "America/Bogota",
    "America/Chicago",
    "America/Denver",
    "America/Halifax",
    "America/Los_Angeles",
    "America/Mexico_City",
    "America/New_York",
    "America/Sao_Paulo",
    "America/Toronto",
    "Asia/Dubai",
    "Asia/Hong_Kong",
    "Asia/Jakarta",
    "Asia/Jerusalem",
    "Asia/Kolkata",
    "Asia/Seoul",
    "Asia/Shanghai",
    "Asia/Singapore",
    "Asia/Tokyo",
    "Australia/Melbourne",
    "Australia/Perth",
    "Australia/Sydney",
    "Europe/Amsterdam",
    "Europe/Berlin",
    "Europe/Dublin",
    "Europe/Istanbul",
    "Europe/Lisbon",
    "Europe/London",
    "Europe/Madrid",
    "Europe/Moscow",
    "Europe/Paris",
    "Europe/Rome",
    "Pacific/Auckland",
    "Pacific/Honolulu"
  ]

  @doc "All offered timezone names, alphabetically with Etc/UTC first."
  def all, do: @timezones

  @doc "Whether the given name is an offered timezone."
  def valid?(timezone), do: timezone in @timezones
end
