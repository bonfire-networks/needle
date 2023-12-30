defmodule Needle.Test.MM do
  use Needle.Mixin,
    otp_app: :needle,
    source: "mm"

  alias Needle.Test.M

  mixin_schema do
    field(:value, :integer)
    has_one(:m, M, foreign_key: :id, references: :id)
  end
end
