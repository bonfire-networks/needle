defmodule Pointers.Pointer do
  @moduledoc """
  A Pointer is a kind of global foreign key that can point to any of
  the tables participating in the abstraction.
  """

  import Pointers.MixProject
  use Ecto.Schema
  alias Pointers.Table

  @primary_key {:id, Pointers.ULID, autogenerate: false}
  @foreign_key_type Pointers.ULID
  
  schema(schema_pointers()) do # TBD if we can use schema_pointers() here
    belongs_to :table, Table
    field :pointed, :any, virtual: true
  end

end
