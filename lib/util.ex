defmodule Pointers.Util do
  @moduledoc false

  @bad_source "You must provide a binary :source option."
  @bad_otp_app "You must provide a valid atom :otp_app option."

  def get_source(opts), do: check_source(Keyword.get(opts, :source))

  defp check_source(x) when is_binary(x), do: x
  defp check_source(_), do: raise ArgumentError, message: @bad_source

  def get_otp_app(opts), do: check_otp_app(Keyword.get(opts, :otp_app))

  defp check_otp_app(x) when is_atom(x), do: x
  defp check_otp_app(_), do: raise ArgumentError, message: @bad_otp_app

  def put_new_attribute(module, attribute, value) do
    if not Module.has_attribute?(module, attribute) do
      quote do
        Module.put_attribute(unquote(module), unquote(attribute), unquote(value))
      end
    else
      quote do
      end
    end
  end

  def schema_foreign_key_type(module),
    do: put_new_attribute(module, :foreign_key_type, Pointers.ULID)

end
