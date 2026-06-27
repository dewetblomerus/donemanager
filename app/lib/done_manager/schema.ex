defmodule DoneManager.Schema do
  @moduledoc """
  Shared schema defaults: UUIDv7 primary/foreign keys and UTC timestamps with
  microseconds. See architecture/database.md and architecture/decisions.md.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, UUIDv7, autogenerate: true}
      @foreign_key_type UUIDv7
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
