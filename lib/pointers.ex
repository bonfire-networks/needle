defmodule Pointers do
  @moduledoc """
  A context for working with Pointers, a sort of global foreign key scheme.
  """

  import Ecto.Query
  alias Pointers.{Pointer, Tables}

  @doc """
  Returns a Pointer, either the one provided or a synthesised one
  pointing to the provided schema object. Does not hit the database or
  cause the pointer to be written to the database whatsoever.
  """
  def cast!(%Pointer{}=p), do: p
  def cast!(%struct{id: id}), do: %Pointer{id: id, table_id: Tables.id!(struct)}

  @doc "Looks up the table for a given pointer"
  def table(%Pointer{table_id: id}), do: Tables.table!(id)

  def schema(%Pointer{table_id: id}), do: Tables.schema!(id)

  @doc """
  Return the provided pointer when it belongs to table queryable by the given table search term.
  """
  def assert_points_to!(%Pointer{table_id: table}=pointer, term) do
    if Tables.id!(term) == table, do: pointer, else: raise ArgumentError
  end

  @doc """
  Given a list of pointers which may or may have their pointed loaded,
  return a plan for preloading, a map of module name to set of loadable IDs.
  """
  def plan(pointers) when is_list(pointers), do: Enum.reduce(pointers, %{}, &plan/2)

  defp plan(%Pointer{pointed: p}, acc) when not is_nil(p), do: acc
  defp plan(%Pointer{id: id, table_id: table}, acc) do
    Map.update(acc, Tables.schema!(table), MapSet.new([id]), &MapSet.put(&1, id))
  end

  @doc """
  Returns a basic query over undeleted pointable objects in the system,
  optionally limited to one or more types.

  If the type is set to a Pointable, Virtual or Mixin schema, records
  will be selected from that schema directly. It is assumed this
  filters deleted records by construction.

  Otherwise, will query from Pointer, filtering not is_nil(deleted_at)
  """
  def query_base(type \\ nil)
  def query_base([]), do: query_base(Pointer)
  def query_base(nil), do: query_base(Pointer)
  def query_base(Pointer), do: from(p in Pointer, where: is_nil(p.deleted_at))
  def query_base(schemas) when is_list(schemas) do
    table_ids = Enum.map(schemas, &get_table_id!/1)
    from(p in query_base(Pointer), where: p.table_id in ^table_ids)
  end
  def query_base(schema) when is_atom(schema) or is_binary(schema) do
    get_table_id!(schema) # ensure it's a pointable or virtual or table id
    from s in schema, select: s
  end

  def get_table_id!(schema) do
    if is_binary(schema), do: schema,
      else: with(nil <- Pointers.Util.table_id(schema), do: need_pointable(schema))
  end

  defp need_pointable(got) do
    raise RuntimeError,
      message: "Expected a table id or pointable or virtual schema module name, got: #{inspect got}"
  end

end
