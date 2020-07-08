defmodule Pointers.Pointer do
  @moduledoc """
  A Pointer is a kind of global foreign key that can point to any of
  the tables participating in the abstraction.
  """
  use Ecto.Schema
  alias Ecto.Changeset
  alias Pointers.{Pointer, Table, Tables, ULID}
  
  schema_module = __MODULE__
  default = "pointers_pointer"



    IO.inspect(p_schema_table_for: schema_module)
    config = Application.get_all_env(:pointers)
    IO.inspect(p_module_config: config)
    table = Pointers.Config.config(schema_module, "source")
    IO.inspect(p_source: table)
    
  
  @primary_key {:id, ULID, autogenerate: false}
  @foreign_key_type ULID
  schema(table) do
    belongs_to :table, Table
    field :pointed, :any, virtual: true
  end

  def create(id \\ Pointers.ULID.generate(), table) do
    table_id = Tables.id!(table)
    Changeset.cast(%Pointer{}, %{id: id, table_id: table_id}, [:id, :table_id])
  end

  def repoint(%Pointer{}=pointer, table) do
    table_id = Tables.id!(table)
    Changeset.cast(pointer, %{table_id: table_id}, [:table_id])
  end

end
