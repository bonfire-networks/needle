defmodule Pointers.Util do
  @moduledoc false

  @bad_source "You must provide a binary :source option."
  @bad_otp_app "You must provide a valid atom :otp_app option."

  @doc """
  Looks up the role for a schema participating in pointers.

  If provided a schema object, uses its `:__struct__`.

  If the provided an atom which is a module name of a schema participating in pointers, returns its
  role (`:mixin`, `:pointable` or `virtual`).

  Anything else returns nil.
  """
  def role(%module{}), do: role(module)
  def role(module) when is_atom(module) do
    if function_exported?(module, :__pointers__, 1),
      do: module.__pointers__(:role)
  end
  def role(_), do: nil

  @doc """
  Looks up the table id for a schema participating in pointers.

  If provided a schema object, uses its `:__struct__`.

  If the provided an atom which is a module name of a virtual or pointable schema, a ULID.

  Anything else returns nil.
  """
  def table_id(%module{}), do: role(module)
  def table_id(module) when is_atom(module) do
    if function_exported?(module, :__pointers__, 1),
      do: module.__pointers__(:table_id)
  end
  def role(_), do: nil

  @doc false # maps a tuple flip over a list
  def flip(list) when is_list(list),
    do: Enum.map(list, fn {k, v} -> {v, k} end)

  def add_binaries(list) when is_list(list) do
    Enum.flat_map(list, fn {k, v} when is_atom(k) and is_atom(v) ->
      [{k, v}, {Atom.to_string(k), Atom.to_string(v)}]
    end)
  end

  # renames keys in a map or keyword list
  def rename(map, changes) when is_map(map) do
    Enum.reduce(changes, map, fn {k, l}, map ->
      case map do
        %{^k => v} -> Map.put(Map.delete(map, k), l, v)
        _ -> map
      end
    end)
  end

  def rename(kw, changes) when is_list(kw) do
    Enum.reduce(changes, kw, fn {k, l}, kw ->
      case Keyword.fetch(kw, k) do
        {:ok, v} -> [{l, v} | Keyword.delete(kw, k)]
        _ -> kw
      end
    end)
  end

  # option processing
  def get_source(opts), do: check_source(Keyword.get(opts, :source))

  defp check_source(x) when is_binary(x), do: x
  defp check_source(_), do: raise ArgumentError, message: @bad_source

  def get_otp_app(opts), do: check_otp_app(Keyword.get(opts, :otp_app))

  defp check_otp_app(x) when is_atom(x), do: x
  defp check_otp_app(_), do: raise ArgumentError, message: @bad_otp_app

  # expands to putting the attribute if it does not already exist
  def put_new_attribute(module, attribute, value) do
    if not Module.has_attribute?(module, attribute) do
      quote do
        Module.put_attribute(unquote(module), unquote(attribute), unquote(value))
      end
    end
  end

  # defaults the foreign key type to ULID
  def schema_foreign_key_type(module),
    do: put_new_attribute(module, :foreign_key_type, Pointers.ULID)

  def pointers_clause(arg, value) do
    quote do
      def __pointers__(unquote(arg)), do: unquote(value)
    end
  end

  # defaults @primary_key
  @doc false
  def schema_primary_key(module, opts) do
    autogen = Keyword.get(opts, :autogenerate, true)
    schema_pk(Module.get_attribute(module, :primary_key), autogen)
  end

  defp schema_pk(nil, autogenerate) do
    data = Macro.escape({:id, Pointers.ULID, autogenerate: autogenerate})
    quote do
      @primary_key unquote(data)
    end
  end
  defp schema_pk(_, _), do: :ok

  @doc "Builds an index of objects by id"
  def index_objects_by_id(items) do
    Enum.reduce(items, %{}, fn item, acc ->
      case item do
        %{id: id} -> Map.put(acc, id, item)
        _ -> acc
      end
    end)
  end
end
