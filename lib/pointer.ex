defmodule Pointers.Pointer do
  @moduledoc """
  A Pointer is a kind of global foreign key that can point to any of
  the tables participating in the abstraction.
  """
  use Ecto.Schema
  alias Ecto.Changeset
  alias Pointers.{Pointer, Table, Tables, ULID}
  require Flexto

  table =
    Application.get_env(:pointers, __MODULE__, [])
    |> Keyword.get(:source, "pointers_pointer")

  @primary_key {:id, ULID, autogenerate: false}
  @foreign_key_type ULID
  schema(table) do
    belongs_to :table, Table
    field :pointed, :any, virtual: true
    field :deleted_at, :utc_datetime_usec
    Flexto.flex_schema(:pointers)
  end

  @doc "Changeset for creating a Pointer"
  def create(id \\ Pointers.ULID.generate(), table) do
    table_id = Tables.id!(table)
    Changeset.cast(%Pointer{}, %{id: id, table_id: table_id}, [:id, :table_id])
  end

  @doc "Changeset for updating which table a Pointer points to."
  def repoint(%Pointer{}=pointer, table) do
    table_id = Tables.id!(table)
    Changeset.cast(pointer, %{table_id: table_id}, [:table_id])
  end

end
