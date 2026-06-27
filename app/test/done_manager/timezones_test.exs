defmodule DoneManager.TimezonesTest do
  use ExUnit.Case, async: true

  alias DoneManager.Timezones

  describe "format/2" do
    test "renders a UTC instant in a fixed-offset household zone" do
      assert Timezones.format(~U[2026-06-27 17:34:00Z], "Africa/Johannesburg") ==
               "2026-06-27 19:34 SAST"
    end

    test "honors daylight saving in the target zone" do
      # New York is EDT (UTC-4) in summer, EST (UTC-5) in winter.
      assert Timezones.format(~U[2026-06-27 17:34:00Z], "America/New_York") ==
               "2026-06-27 13:34 EDT"

      assert Timezones.format(~U[2026-01-15 17:34:00Z], "America/New_York") ==
               "2026-01-15 12:34 EST"
    end

    test "falls back to UTC for an unknown zone" do
      assert Timezones.format(~U[2026-06-27 17:34:00Z], "Mars/Olympus") ==
               "2026-06-27 17:34 UTC"
    end
  end
end
