defmodule Needle.Test.M do
  use Needle.Mixin,
    otp_app: :needle,
    source: "m"

  alias Needle.Test.P

  mixin_schema do
    field(:value, :integer)
    belongs_to(:p, P, references: :id)
  end
end
