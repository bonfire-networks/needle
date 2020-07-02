defmodule Pointers.Mixin do
  @moduledoc """
  
  """

  # alias Ecto.Changeset
  alias Pointers.Util

  defmacro __using__(options), do: using(__CALLER__.module, options)

  @must_be_in_module "Pointers.Mixin may only be used inside a defmodule!"

  def using(nil, _options), do: raise CompileError, description: @must_be_in_module
  def using(module, options) do
    Util.get_source(options)
    Util.get_otp_app(options)
    Module.put_attribute(module, __MODULE__, options)
    quote do
      use Ecto.Schema
      import Flexto
      import Pointers.Mixin
    end
  end

  @must_use "You must use Pointers.Mixin before calling mixin_schema/1"

  defmacro mixin_schema([do: body]) do
    module = __CALLER__.module
    schema_check_attr(Module.get_attribute(module, __MODULE__), module, body)
  end
  
  @default_timestamps_opts [type: :utc_datetime_usec]

  defp schema_check_attr(options, module, body) when is_list(options) do
    otp_app = Keyword.fetch!(options, :otp_app)
    config = Application.get_env(otp_app, module, [])
    source = Util.get_source(config ++ options)
    Util.put_new_attribute(module, :primary_key, false) # hope you know what you're doing...
    Util.schema_foreign_key_type(module)
    Util.put_new_attribute(module, :timestamps_opts, @default_timestamps_opts)
    quote do
      schema(unquote(source)) do
        belongs_to :pointer, Pointers.Pointer,
          foreign_key: :id,
          on_replace: :update,
          primary_key: true,
          type: Pointers.ULID
        unquote(body)
        Flexto.flex_schema(unquote(otp_app))
      end
    end
  end

  defp schema_check_attr(_, _, _), do: raise ArgumentError, message: @must_use

end
