defmodule Pointers.Table do
  @moduledoc """
  One Table to rule them all. A record of a table participating in the
  pointers abstraction - mandatory if participating.
  """

  use Pointers.Schema
  import Ecto.Schema

  @type t :: %Pointers.Table{
    table: binary,
    schema: atom | nil,
    pointed: term,
  }

  pointable_schema("pointers_table", "P01NTERTAB1EF0RA11TAB1ES00", false) do
    field :table, :string
    field :schema, :any, virtual: true
    field :pointed, :any, virtual: true 
  end
  
end
