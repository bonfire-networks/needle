defmodule Pointers.Schema do
  @moduledoc "Some macros to help you define schemas."

  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      import Pointers.Schema
    end
  end

  @doc """
  Define a schema for a table participating in the pointers
  abstraction. Takes a UUID in text form which is a sentinel value
  used to identify the table. It *must* match the one inserted into
  `Table` in the migrations that create this table.
  """
  defmacro pointable_schema(table, id, autogenerate \\ true, body) do
    Pointers.ULID.cast!(id)
    quote do
      Pointers.Schema.ulid_schema(unquote(table), unquote(autogenerate), unquote(body))
      def table_id(), do: unquote(id)
    end
  end

  @doc """
  Define a table schema with a ULID as a primary key but that is not
  participating in the pointers abstraction.
  """
  defmacro ulid_schema(table, autogenerate \\ true, body) do
    quote do
      @primary_key {:id, Pointers.ULID, autogenerate: unquote(autogenerate)}
      @foreign_key_type Pointers.ULID
      @timestamps_opts [type: :utc_datetime_usec, inserted_at: false]
      schema(unquote(table), unquote(body))
    end
  end

end
