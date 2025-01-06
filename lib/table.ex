defmodule Needle.Table do
  @moduledoc """
  One Table to rule them all. A record of a table participating in the
  pointers abstraction - mandatory if participating.
  """

  use Needle.Pointable,
    otp_app: :needle,
    source: "pointers_table",
    table_id: "601NTERTAB1EF0RA11TAB1ES00",
    autogenerate: false

  # import Ecto.Schema

  # @type t :: %Needle.Table{
  #         table: binary,
  #         schema: atom | nil,
  #         pointed: term | nil
  #       }

  pointable_schema do
    field(:table, :string)
    field(:schema, :any, virtual: true)
    field(:pointed, :any, virtual: true)
  end
end
