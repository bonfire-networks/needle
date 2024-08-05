defmodule Needle.Pointer do
  @moduledoc """
  A Pointer is any object that can be referenced by its id.

  Pointer is a simple table consisting of three fields:
  * id - the database-unique id for this pointer in ULID format.
  * table_id - a type tag, references `Table`.
  * deleted_at - timestamp of when the object was deleted, null by default.

  To reference `any` object, simply reference `Pointer`:

  ```
  alias Needle.Pointer
  belongs_to :object, Pointer
  ```

  To define a new object type there are two options, you should choose one:

  * `Virtual` - an object type with a view over `Pointer` limited by type.
  * `Pointable` - an object type with a table which is kept synchronised with `Pointer`.

  For most purposes, you should use a `Virtual`. Pointable exists mostly to support existing code.
  The major difference in practice is that you cannot add new fields to a virtual. Most of the time
  you will want to store such extra fields in one or more mixins anyway so they may be reused.

  See `Mixin` for more information about mixins.
  """
  use Ecto.Schema
  alias Ecto.Changeset
  alias Needle.{Pointer, Table, Tables, ULID}
  use Exto

  table =
    Application.compile_env(:needle, __MODULE__, [])
    |> Keyword.get(:source, "pointers_pointer")

  @primary_key {:id, ULID, autogenerate: false}
  @foreign_key_type ULID
  schema(table) do
    belongs_to(:table, Table)
    field(:pointed, :any, virtual: true)
    field(:deleted_at, :utc_datetime_usec)
    Exto.flex_schema(:needle)
  end

  @doc "Changeset for creating a Pointer"
  def create(id \\ Needle.ULID.generate(), table) do
    table_id = Tables.id!(table)
    Changeset.cast(%Pointer{}, %{id: id, table_id: table_id}, [:id, :table_id])
  end

  # "Changeset for updating which table a Pointer points to."
  @doc false
  def repoint(%Pointer{} = pointer, table) do
    table_id = Tables.id!(table)
    Changeset.cast(pointer, %{table_id: table_id}, [:table_id])
  end
end
