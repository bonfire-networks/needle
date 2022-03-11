defmodule Pointers.Test.P do
  use Pointers.Pointable,
    otp_app: :pointers,
    table_id: "01FXJXJMDV2DACPNDS3SZYTB75",
    source: "p"

  alias Pointers.Test.{M, MM, P}
  pointable_schema do
    belongs_to :p, P, foreign_key: :id, define_field: :false
    has_one :m, M, foreign_key: :id, references: :id
    has_many :mm, MM, foreign_key: :id, references: :id
    field :value, :integer
  end

end
