defmodule Pointers.Test.M do
  use Pointers.Mixin,
    otp_app: :pointers,
    source: "m"

  alias Pointers.Test.P

  mixin_schema do
    field(:value, :integer)
    belongs_to(:p, P, references: :id)
  end
end
