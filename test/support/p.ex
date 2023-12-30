defmodule Needle.Test.P do
  use Needle.Pointable,
    otp_app: :needle,
    table_id: "01FXJXJMDV2DACPNDS3SZYTB75",
    source: "p"

  alias Needle.Test.{M, MM, P}

  pointable_schema do
    belongs_to(:p, P, foreign_key: :id, define_field: false)
    has_one(:m, M, foreign_key: :id, references: :id)
    has_many(:mm, MM, foreign_key: :id, references: :id)
    field(:value, :integer)
  end
end
