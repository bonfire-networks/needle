defmodule Pointers.Pointable do
  @moduledoc """
  Sets up an Ecto Schema for a Pointable table.

  ## Sample Usage

  ```
  use Pointers.Pointable,
    otp_app: :my_app,   # your OTP application's name
    source: "my_table", # default name of table in database
    table_id: "01EBTVSZJ6X02J01R1XWWPWGZW" # valid ULID to identify table
  ```
  """

  alias Pointers.Util

  defmacro __using__(options), do: using(__CALLER__.module, options)

  @must_be_in_module "Pointers.Pointable may only be used inside a defmodule!"

  defp using(nil, _options), do: raise CompileError, description: @must_be_in_module
  defp using(module, options) do
    # raise early if not present
    Util.get_source(options)
    Util.get_otp_app(options)
    get_table_id(options)
    app = Keyword.fetch!(options, :otp_app)
    Module.put_attribute(module, __MODULE__, options)
    config = Application.get_env(app, module, [])
    pointable = emit_pointable(config ++ options)
    quote do
      use Ecto.Schema
      require Flexto
      import Pointers.Pointable
      unquote_splicing(pointable)
    end
  end

  @bad_table_id "You must provide a ULID-formatted binary :table_id option."
  @must_use "You must use Pointers.Pointable before calling pointable_schema/1."

  defp get_table_id(opts), do: check_table_id(Keyword.get(opts, :table_id))
  
  defp check_table_id(x) when is_binary(x), do: check_table_id_valid(x, Pointers.ULID.cast(x))
  defp check_table_id(_), do: raise ArgumentError, message: @bad_table_id

  defp check_table_id_valid(x, {:ok, x}), do: x
  defp check_table_id_valid(_, _), do: raise ArgumentError, message: @bad_table_id

  defmacro pointable_schema(body)
  defmacro pointable_schema([do: body]) do
    module = __CALLER__.module
    schema_check_attr(Module.get_attribute(module, __MODULE__), module, body)
  end

  @default_timestamps_opts [type: :utc_datetime_usec]

  # verifies that the module was `use`d and generates a new schema
  defp schema_check_attr(options, module, body) when is_list(options) do
    otp_app = Keyword.fetch!(options, :otp_app)
    config = Application.get_env(otp_app, module, [])
    source = Util.get_source(config ++ options)
    schema_primary_key(module, options)
    Util.schema_foreign_key_type(module)
    Util.put_new_attribute(module, :timestamps_opts, @default_timestamps_opts)
    quote do
      schema unquote(source) do
        unquote(body)
        Flexto.flex_schema(unquote(otp_app))
      end
    end
  end

  defp schema_check_attr(_, _, _), do: raise CompileError, message: @must_use

  # defaults @primary_key
  defp schema_primary_key(module, opts) do
    autogen = Keyword.get(opts, :autogenerate, true)
    schema_pk(Module.get_attribute(module, :primary_key), module, autogen)
  end

  defp schema_pk(nil, module, autogenerate) do
    data = {:id, Pointers.ULID, autogenerate: autogenerate}
    Module.put_attribute(module, :primary_key, data)
  end
  defp schema_pk(_, _, _), do: :ok

  # defines __pointable__
  defp emit_pointable(config) do
    table_id = Pointers.ULID.cast!(Keyword.fetch!(config, :table_id))
    otp_app = Keyword.fetch!(config, :otp_app)
    [ pointable_clause(:table_id, table_id),
      pointable_clause(:otp_app, otp_app) ]
  end

  defp pointable_clause(arg, value) do
    quote do
      def __pointable__(unquote(arg)), do: unquote(value)
    end
  end

end
