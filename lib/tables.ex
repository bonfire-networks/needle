defmodule Pointers.Tables do
  @moduledoc """
  A Global cache of Tables to be queried by their (Pointer) IDs, table
  names or Ecto Schema module names.

  Use of the Table Service requires:

  1. You have run the migrations shipped with this library.
  2. You have started `Pointers.Tables` before querying.
  3. All OTP applications with pointable Ecto Schemata to be added to the schema path.
  4. OTP 21.2 or greater, though we recommend using the most recent release available.

  While this module is a GenServer, it is only responsible for setup
  of the cache and then exits with :ignore having done so. It is not
  recommended to restart the service as this will lead to a stop the
  world garbage collection of all processes and the copying of the
  entire cache to each process that has queried it since its last
  local garbage collection.
  """  
  alias Pointers.{NotFound, Table, ULID}

  use GenServer, restart: :transient

  @typedoc """
  A query is either a table's (database) name or (Pointer) ID as a
  binary or the name of its Ecto Schema Module as an atom.
  """
  @type query :: binary | atom

  @spec start_link(ignored :: term) :: GenServer.on_start()
  @doc "Populates the global cache with table data via introspection."
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  def data(), do: :persistent_term.get(__MODULE__)


  @spec table(query :: query) :: {:ok, Table.t} | {:error, NotFound.t}
  @doc "Get a Table identified by name, id or module."
  def table(query) when is_binary(query) or is_atom(query) do
    case Map.get(data(), query) do
      nil -> {:error, NotFound.new()}
      other -> {:ok, other}
    end
  end

  @spec table!(query) :: Table.t
  @doc "Look up a Table by name or id, raise NotFound if not found."
  def table!(query), do: Map.get(data(), query) || raise(NotFound)

  @spec id(query) :: {:ok, integer()} | {:error, TableNotFoundError.t()}
  @doc "Look up a table id by id, name or schema."
  def id(query), do: with( {:ok, val} <- table(query), do: {:ok, val.id})

  @spec id!(query) :: integer()
  @doc "Look up a table id by id, name or schema, raise NotFound if not found."
  def id!(query) when is_atom(query) or is_binary(query), do: id!(query, data())
    
  @spec ids!([binary | atom]) :: [binary]
  @doc "Look up many ids at once, raise NotFound if any of them are not found"
  def ids!(ids) do
    data = data()
    Enum.map(ids, &id!(&1, data))
  end

  # called by id!/1, ids!/1
  defp id!(query, data), do: Map.get(data, query).id || raise(NotFound)

  @spec schema(query) :: {:ok, atom} | {:error, NotFound.t}
  @doc "Look up a schema module by id, name or schema"
  def schema(query), do: with({:ok, val} <- table(query), do: {:ok, val.schema})

  @spec schema!(query) :: atom
  @doc "Look up a schema module by id, name or schema, raise NotFound if not found"
  def schema!(query), do: table!(query).schema

  # GenServer callback

  @doc false
  def init(_) do
    indexed =
      search_path()
      |> Enum.flat_map(&app_modules/1)
      |> Enum.filter(&pointer_schema?/1)
      |> Enum.reduce(%{}, &index/2)
    :persistent_term.put(__MODULE__, indexed)
    :ignore
  end

  defp app_modules(app), do: app_modules(app, Application.spec(app, :modules))
  defp app_modules(_, nil), do: []
  defp app_modules(_, mods), do: mods
  # called by init/1
  defp search_path(), do: [:pointers | Application.fetch_env!(:pointers, :search_path)]

  # called by init/1
  defp pointer_schema?(module) do
    function_exported?(module, :table_id, 0) and function_exported?(module, :__schema__, 1)
  end

  # called by init/1
  defp index(mod, acc), do: index(mod, acc, mod.__schema__(:primary_key))
  # called by index/2
  defp index(mod, acc, [:id]), do: index(mod, acc, mod.__schema__(:type, :id))
  # called by index/3, the line above
  defp index(mod, acc, ULID), do: index(mod, acc, mod.table_id(), mod.__schema__(:source))
  # doesn't look right, skip it
  defp index(_, acc, _), do: acc

  # called by index/3
  defp index(mod, acc, id, table) do
    t = %Table{ id: id, schema: mod, table: table}
    Map.merge(acc, %{id => t, table => t, mod => t})
  end

end
