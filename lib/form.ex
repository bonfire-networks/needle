defmodule Pointers.Form do
  @moduledoc """

  """

  # alias Ecto.Changeset
  alias Pointers.{ULID, Util}

  defmacro __using__(options), do: using(__CALLER__.module, options)

  @must_be_in_module "Pointers.Form may only be used inside a defmodule!"

  def using(nil, _options),
    do: raise(CompileError, description: @must_be_in_module)

  def using(module, options) do
    otp_app = Util.get_otp_app(options)
    config = Application.get_env(otp_app, module, [])
    Module.put_attribute(module, __MODULE__, options)
    pointers = emit_pointers(config ++ options)

    quote do
      use Ecto.Schema
      require Pointers.Changesets
      import Flexto
      import Pointers.Form
      unquote_splicing(pointers)
    end
  end

  @must_use "You must use Pointers.Form before calling form_schema/1"

  defmacro form_schema(do: body) do
    module = __CALLER__.module
    schema_check_attr(Module.get_attribute(module, __MODULE__), module, body)
  end

  @foreign_key_type ULID

  defp schema_check_attr(options, module, body) when is_list(options) do
    otp_app = Util.get_otp_app(options)

    foreign_key = Module.get_attribute(module, :foreign_key_type, @foreign_key_type)

    quote do
      @primary_key false
      @foreign_key_type unquote(foreign_key)
      embedded_schema do
        unquote(body)
        Flexto.flex_schema(unquote(otp_app))
      end
    end
  end

  defp schema_check_attr(_, _, _), do: raise(ArgumentError, message: @must_use)

  # defines __pointers__
  defp emit_pointers(config) do
    otp_app = Keyword.fetch!(config, :otp_app)

    [
      Util.pointers_clause(:role, :form),
      Util.pointers_clause(:otp_app, otp_app)
    ]
  end
end
