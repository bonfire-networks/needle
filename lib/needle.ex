defmodule Needle do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  def is_needle?(
        schema_or_struct,
        one_of_types \\ [:pointable, :virtual, :mixin, :unpointable, :random, :form]
      )

  def is_needle?(%struct{}, one_of_types), do: is_needle?(struct, one_of_types)

  def is_needle?(schema, one_of_types)
      when is_atom(schema) and not is_nil(schema) and is_list(one_of_types),
      do:
        function_exported?(schema, :__pointers__, 1) and
          schema.__pointers__(:role) in one_of_types

  def is_needle?(_, _), do: false
  
end
