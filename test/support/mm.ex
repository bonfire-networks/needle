defmodule Pointers.Test.MM do
  use Pointers.Mixin,
    otp_app: :pointers,
    source: "mm"

  alias Pointers.Test.M

  mixin_schema do
    field(:value, :integer)
    has_one(:m, M, foreign_key: :id, references: :id)
  end
end
