defmodule Pointers do
  @moduledoc """
  A context for working with Pointers, a sort of global foreign key scheme.
  """

  alias Pointers.{Pointer, Tables}

  @doc """
  Returns a Pointer, either the one provided or a synthesised one
  pointing to the provided schema object. Does not hit the database or
  cause the pointer to be written to the database whatsoever.
  """
  def cast!(%Pointer{}=p), do: p
  def cast!(%struct{id: id}), do: %Pointer{id: id, table_id: Tables.id!(struct)}

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
    
end
