defmodule Needle.Migration.Indexable do
  @moduledoc "Helpers for creating indexes on pointer fields in migrations."

  import Ecto.Migration
  import Needle.Migration

  defmacro __using__(_opts \\ []) do
    quote do
      import Ecto.Migration
      import Needle.Migration
      import Needle.Migration.Indexable
      @disable_ddl_transaction true
    end
  end

 @doc """
  Adds a pointer field and an index for it. Note: this uses `alter table` and can't be run in the same migration as the `create table` call for the same table.

  ## Example
      create_pointer_with_index(:my_table, :thread_id, :strong, Needle.Pointer, unique: false)
  """
  def create_pointer_with_index(table_name, field, type, ref_table \\ Pointer, opts \\ []) do
    alter table(table_name) do
      add_pointer_if_not_exists(field, type, ref_table, opts)
    end
    create_index_for_pointer(table_name, field, opts)
  end

  @doc """
  Creates index for a pointer field on a table.
  """
  def create_index_for_pointer(table_name, fields, opts \\ []) do
    create_if_not_exists(index(table_name, List.wrap(fields), Keyword.put_new(opts, :concurrently, true)))
  end

  @doc """
  Bulk-creates indexes for pointer fields on a table.

  ## Examples

      create_indexes_for_pointers(:my_table, [:user_id, :thread_id])
      create_indexes_for_pointers(:my_table, [user_id: [unique: true], thread_id: [unique: false]], [where: "deleted_at IS NULL"])
  """
  def create_indexes_for_pointers(table_name, fields, opts \\ []) do
    Enum.each(fields, fn
      {field, field_opts} when is_list(field_opts) ->
        create_index_for_pointer(table_name, field, Keyword.merge(opts, field_opts))

      field ->
        create_index_for_pointer(table_name, field, opts)
    end)
  end

end
