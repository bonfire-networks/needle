defmodule Needle.Unpointable do
  @moduledoc """
  Has a ULID primary key but is not pointable.
  """

  # alias Ecto.Changeset
  alias Needle.{ULID, Util}

  defmacro __using__(options), do: using(__CALLER__.module, options)

  @must_be_in_module "Needle.Unpointable may only be used inside a defmodule!"

  def using(nil, _options),
    do: raise(CompileError, description: @must_be_in_module)

  def using(module, options) do
    otp_app = Util.get_otp_app(options)
    Util.get_source(options)
    config = Application.get_env(otp_app, module, [])
    Module.put_attribute(module, __MODULE__, options)
    pointers = emit_pointers(config ++ options)

    quote do
      use Ecto.Schema
      require Needle.Changesets
      import Exto
      import Needle.Unpointable
      unquote_splicing(pointers)
    end
  end

  @must_use "You must use Needle.Unpointable before calling unpointable_schema/1"

  defmacro unpointable_schema(do: body) do
    module = __CALLER__.module
    schema_check_attr(Module.get_attribute(module, __MODULE__), module, body)
  end

  @timestamps_opts [type: :utc_datetime_usec]
  @foreign_key_type ULID

  defp schema_check_attr(options, module, body) when is_list(options) do
    otp_app = Util.get_otp_app(options)
    config = Application.get_env(otp_app, module, [])
    source = Util.get_source(config ++ options)

    foreign_key = Module.get_attribute(module, :foreign_key_type, @foreign_key_type)

    timestamps_opts = Module.get_attribute(module, :timestamps_opts, @timestamps_opts)

    quote do
      unquote(schema_primary_key(module, options))
      @foreign_key_type unquote(foreign_key)
      @timestamps_opts unquote(timestamps_opts)
      schema(unquote(source)) do
        unquote(body)
        Exto.flex_schema(unquote(otp_app))
      end
    end
  end

  defp schema_check_attr(_, _, _), do: raise(ArgumentError, message: @must_use)

  # defaults @primary_key
  defp schema_primary_key(module, opts) do
    autogen = Keyword.get(opts, :autogenerate, true)
    schema_pk(Module.get_attribute(module, :primary_key), autogen)
  end

  defp schema_pk(nil, autogenerate) do
    data = Macro.escape({:id, Needle.ULID, autogenerate: autogenerate})

    quote do
      @primary_key unquote(data)
    end
  end

  defp schema_pk(_, _), do: :ok

  # defines __pointers__
  defp emit_pointers(config) do
    otp_app = Keyword.fetch!(config, :otp_app)

    [
      Util.pointers_clause(:role, :unpointable),
      Util.pointers_clause(:otp_app, otp_app)
    ]
  end
end
