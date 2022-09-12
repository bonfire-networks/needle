defmodule Pointers.NotFound do
  @moduledoc "We could not find the requested object"
  defexception [:message, :code]

  @type t :: %Pointers.NotFound{
          message: binary,
          code: 404
        }

  @doc "Creates a new NotFound"
  @spec new() :: t
  def new(name \\ "Pointer"),
    do: %__MODULE__{message: "#{name} Not Found", code: 404}

  @doc false
  def exception(_), do: new()
end
